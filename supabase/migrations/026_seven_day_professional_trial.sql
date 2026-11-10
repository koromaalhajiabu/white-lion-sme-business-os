-- White Lion SME OS — Migration 026
-- Start a seven-day Professional trial for newly created business workspaces.
-- Existing subscriptions and existing business workspaces are not modified.
begin;

create or replace function public.create_business(
  p_name text,
  p_industry text default 'Multi-industry',
  p_currency_code text default 'SLE'
)
returns uuid
language plpgsql
security definer
set search_path to 'public', 'auth'
as $function$
declare
  v_business_id uuid;
  v_user_id uuid;
  v_business_count integer;
  v_business_limit integer;
  v_trial_ends_at timestamptz;
begin
  v_user_id := auth.uid();

  if v_user_id is null then
    raise exception 'Authentication required';
  end if;

  if length(trim(coalesce(p_name, ''))) < 2 then
    raise exception 'Business name is required';
  end if;

  -- Prevent concurrent requests from bypassing the user's registration limit.
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

  -- New workspaces begin with a no-card, seven-day Professional trial.
  v_trial_ends_at := now() + interval '7 days';
  insert into public.business_subscriptions(
    business_id, plan_code, status, currency_code, billing_cycle,
    current_period_start, trial_ends_at, created_at, updated_at
  )
  values (
    v_business_id, 'professional', 'trial', 'SLE', 'monthly',
    now(), v_trial_ends_at, now(), now()
  );

  insert into public.subscription_events(
    business_id, actor_user_id, event_type, details
  )
  values (
    v_business_id, v_user_id, 'trial_started',
    jsonb_build_object(
      'plan_code', 'professional',
      'trial_days', 7,
      'trial_ends_at', v_trial_ends_at,
      'payment_required_at_signup', false
    )
  );

  insert into public.audit_logs(business_id, action, entity_table, entity_id)
  values (v_business_id, 'business_created', 'businesses', v_business_id::text);

  return v_business_id;
end;
$function$;

revoke all on function public.create_business(text, text, text) from public, anon;
grant execute on function public.create_business(text, text, text) to authenticated;

commit;
