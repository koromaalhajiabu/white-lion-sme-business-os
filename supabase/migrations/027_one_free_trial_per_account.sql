-- White Lion SME OS — Migration 027
-- Enforce one Professional free trial per authenticated account, not per workspace.
-- Existing subscriptions are preserved and count as an already-used trial entitlement.
-- Additional workspaces can still be registered when the developer grants permission,
-- but they require a paid subscription if the account has already claimed its trial.

begin;

create table if not exists public.platform_trial_claims (
  user_id uuid primary key references auth.users(id) on delete cascade,
  first_business_id uuid not null,
  claimed_at timestamptz not null default now(),
  trial_ends_at timestamptz
);

comment on table public.platform_trial_claims is
  'Permanent account-level record of the one-time free trial entitlement. first_business_id intentionally has no FK so deleting a workspace cannot reset the claim.';

alter table public.platform_trial_claims enable row level security;
revoke all on public.platform_trial_claims from public, anon, authenticated;

-- Preserve all existing subscription history as a consumed trial entitlement.
-- This prevents accounts with a prior trial, paid plan, or pending invoice from
-- receiving another free trial merely by registering another workspace.
insert into public.platform_trial_claims(user_id, first_business_id, claimed_at, trial_ends_at)
select distinct on (b.owner_user_id)
  b.owner_user_id,
  b.id,
  coalesce(s.created_at, now()),
  s.trial_ends_at
from public.business_subscriptions s
join public.businesses b on b.id = s.business_id
where b.owner_user_id is not null
order by b.owner_user_id, s.created_at asc, b.id asc
on conflict (user_id) do nothing;

-- Remove the earlier per-business trigger. Trial allocation now happens atomically
-- inside create_business, alongside the user's business-registration limit check.
drop trigger if exists start_business_free_trial on public.businesses;
drop function if exists public.start_new_business_trial();

create or replace function public.create_business(
  p_name text,
  p_industry text default 'Multi-industry',
  p_currency_code text default 'SLE'
)
returns uuid
language plpgsql
security definer
set search_path = ''
as $function$
declare
  v_business_id uuid;
  v_user_id uuid;
  v_business_count integer;
  v_business_limit integer;
  v_trial_start timestamptz := now();
  v_trial_end timestamptz := now() + interval '7 days';
  v_trial_claimed_user uuid;
  v_trial_granted boolean := false;
  v_subscription_currency text;
begin
  v_user_id := auth.uid();

  if v_user_id is null then
    raise exception 'Authentication required';
  end if;

  if length(trim(coalesce(p_name, ''))) < 2 then
    raise exception 'Business name is required';
  end if;

  -- Serialize registrations for this account to prevent concurrent limit/trial bypass.
  perform pg_advisory_xact_lock(hashtextextended(v_user_id::text, 0));

  if not public.is_platform_developer() then
    select count(*)::integer
      into v_business_count
    from public.businesses
    where owner_user_id = v_user_id;

    select coalesce(
      (select l.max_businesses
       from public.platform_business_registration_limits l
       where l.user_id = v_user_id),
      1
    )
    into v_business_limit;

    if v_business_count >= v_business_limit then
      raise exception
        'Business registration limit reached. Your current limit is % business(es). Contact the platform developer to request authorization for additional businesses.',
        v_business_limit;
    end if;
  end if;

  if not exists (
    select 1
    from public.subscription_plans
    where code = 'professional'
      and is_active = true
  ) then
    raise exception 'The Professional plan is unavailable; business registration cannot continue';
  end if;

  insert into public.businesses(name, industry, currency_code, owner_user_id)
  values (
    trim(p_name),
    coalesce(nullif(trim(p_industry), ''), 'Multi-industry'),
    upper(coalesce(nullif(trim(p_currency_code), ''), 'SLE')),
    v_user_id
  )
  returning id into v_business_id;

  insert into public.business_members(business_id, user_id, role)
  values (v_business_id, v_user_id, 'owner');

  insert into public.branches(business_id, name)
  values (v_business_id, 'Main Branch');

  -- The primary key on user_id guarantees one trial per account, even if the
  -- user has permission to create multiple businesses or deletes an old workspace.
  insert into public.platform_trial_claims(
    user_id, first_business_id, claimed_at, trial_ends_at
  )
  values (v_user_id, v_business_id, v_trial_start, v_trial_end)
  on conflict (user_id) do nothing
  returning user_id into v_trial_claimed_user;

  v_trial_granted := v_trial_claimed_user is not null;
  v_subscription_currency := case
    when upper(coalesce(nullif(trim(p_currency_code), ''), 'SLE')) = 'USD' then 'USD'
    else 'SLE'
  end;

  if v_trial_granted then
    insert into public.business_subscriptions(
      business_id, plan_code, status, currency_code, billing_cycle,
      current_period_start, current_period_end, trial_ends_at, grace_until,
      created_at, updated_at
    )
    values (
      v_business_id, 'professional', 'trial', v_subscription_currency, 'monthly',
      v_trial_start, v_trial_end, v_trial_end, null,
      v_trial_start, v_trial_start
    );

    insert into public.subscription_events(
      business_id, actor_user_id, event_type, details
    )
    values (
      v_business_id, v_user_id, 'free_trial_started',
      jsonb_build_object(
        'plan_code', 'professional',
        'trial_days', 7,
        'trial_started_at', v_trial_start,
        'trial_ends_at', v_trial_end,
        'payment_required_at_signup', false,
        'trial_policy', 'one_per_account'
      )
    );
  else
    insert into public.business_subscriptions(
      business_id, plan_code, status, currency_code, billing_cycle,
      current_period_start, current_period_end, trial_ends_at, grace_until,
      created_at, updated_at
    )
    values (
      v_business_id, 'professional', 'pending_payment', v_subscription_currency, 'monthly',
      null, null, null, null,
      v_trial_start, v_trial_start
    );

    insert into public.subscription_events(
      business_id, actor_user_id, event_type, details
    )
    values (
      v_business_id, v_user_id, 'free_trial_not_available',
      jsonb_build_object(
        'plan_code', 'professional',
        'reason', 'This account has already used its one-time free trial.',
        'payment_required_at_signup', true,
        'trial_policy', 'one_per_account'
      )
    );
  end if;

  insert into public.audit_logs(business_id, action, entity_table, entity_id)
  values (v_business_id, 'business_created', 'businesses', v_business_id::text);

  return v_business_id;
end;
$function$;

revoke all on function public.create_business(text, text, text) from public, anon;
grant execute on function public.create_business(text, text, text) to authenticated;

commit;
