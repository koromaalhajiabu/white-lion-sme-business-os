-- White Lion SME OS — Migration 025
-- Seven-day subscription grace period, expiry processing, access status and plan-capacity correction.
-- Existing businesses without a subscription remain grandfathered. No business records are deleted.
begin;

create or replace function public.process_subscription_expirations()
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_grace_started integer := 0;
  v_expired integer := 0;
begin
  with transitioned as (
    update public.business_subscriptions s
       set status = case
             when coalesce(s.current_period_end, s.trial_ends_at) + interval '7 days' <= now()
               then 'expired'
             else 'grace_period'
           end,
           grace_until = coalesce(s.current_period_end, s.trial_ends_at) + interval '7 days',
           updated_at = now()
     where s.status in ('active','trial')
       and coalesce(s.current_period_end, s.trial_ends_at) <= now()
    returning s.business_id, s.status, s.grace_until
  )
  insert into public.subscription_events(business_id,event_type,details)
  select business_id,
         case when status='expired' then 'subscription_expired' else 'subscription_grace_started' end,
         jsonb_build_object('grace_until',grace_until,'grace_days',7)
    from transitioned;

  get diagnostics v_grace_started = row_count;

  with transitioned as (
    update public.business_subscriptions
       set status='expired', updated_at=now()
     where status='grace_period'
       and grace_until is not null
       and grace_until <= now()
    returning business_id, grace_until
  )
  insert into public.subscription_events(business_id,event_type,details)
  select business_id,'subscription_expired',
         jsonb_build_object('grace_until',grace_until)
    from transitioned;

  get diagnostics v_expired = row_count;

  return jsonb_build_object('grace_started_or_immediately_expired',v_grace_started,
                            'grace_periods_expired',v_expired,
                            'processed_at',now());
end;
$$;

create or replace function public.get_business_subscription_access(p_business_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_sub public.business_subscriptions%rowtype;
  v_found boolean := false;
  v_allowed boolean := true;
  v_reason text := 'No subscription is recorded; existing workspace access is preserved.';
begin
  if auth.uid() is null then
    raise exception 'Authentication required';
  end if;
  if not public.has_business_role(p_business_id, enum_range(null::public.business_role)) then
    raise exception 'You are not a member of this business workspace';
  end if;

  perform public.process_subscription_expirations();

  select * into v_sub
    from public.business_subscriptions
   where business_id=p_business_id;
  v_found := found;

  if v_found then
    v_allowed := (
      (v_sub.status='active' and (v_sub.current_period_end is null or v_sub.current_period_end>now()))
      or (v_sub.status='trial' and (v_sub.trial_ends_at is null or v_sub.trial_ends_at>now()))
      or (v_sub.status='grace_period' and v_sub.grace_until is not null and v_sub.grace_until>now())
    );
    v_reason := case
      when v_allowed and v_sub.status='grace_period'
        then 'Your subscription is in its seven-day renewal grace period.'
      when v_allowed then 'Subscription access is active.'
      when v_sub.status='expired' then 'The subscription and its seven-day grace period have expired. Renew to restore online access.'
      when v_sub.status='suspended' then 'This subscription has been suspended. Contact White Lion support.'
      when v_sub.status='cancelled' then 'This subscription is cancelled. Choose a plan to restore access.'
      else 'A verified subscription is required to continue using this workspace online.'
    end;
  end if;

  return jsonb_build_object(
    'has_subscription',v_found,
    'allowed',v_allowed,
    'status',case when v_found then v_sub.status else 'grandfathered' end,
    'plan_code',v_sub.plan_code,
    'current_period_end',v_sub.current_period_end,
    'grace_until',v_sub.grace_until,
    'reason',v_reason
  );
end;
$$;

-- Update branch capacity enforcement so a valid grace period is honoured.
create or replace function public.enforce_business_branch_capacity()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_max_branches integer;
  v_status text;
  v_period_end timestamptz;
  v_grace_until timestamptz;
  v_trial_end timestamptz;
  v_branch_count integer;
begin
  if new.is_active is not true then return new; end if;
  perform 1 from public.businesses where id=new.business_id for update;
  if not found then raise exception 'Business workspace not found'; end if;

  select p.max_branches,s.status,s.current_period_end,s.grace_until,s.trial_ends_at
    into v_max_branches,v_status,v_period_end,v_grace_until,v_trial_end
    from public.business_subscriptions s
    join public.subscription_plans p on p.code=s.plan_code and p.is_active=true
   where s.business_id=new.business_id
   for update of s;

  if not found then return new; end if;

  if not (
    (v_status='active' and (v_period_end is null or v_period_end>now()))
    or (v_status='trial' and (v_trial_end is null or v_trial_end>now()))
    or (v_status='grace_period' and v_grace_until is not null and v_grace_until>now())
  ) then
    raise exception 'An active subscription or valid grace period is required before adding another branch. Open Plans & Billing to renew.';
  end if;

  select count(*)::integer into v_branch_count
    from public.branches
   where business_id=new.business_id and is_active=true
     and (tg_op<>'UPDATE' or id<>new.id);
  if v_branch_count>=v_max_branches then
    raise exception 'Your subscription allows a maximum of % active branch(es). Upgrade your plan in Plans & Billing to add another branch.',v_max_branches;
  end if;
  return new;
end;
$$;

-- Update member capacity enforcement with the same subscription/grace-period rules.
create or replace function public.enforce_business_user_capacity()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_max_users integer;
  v_status text;
  v_period_end timestamptz;
  v_grace_until timestamptz;
  v_trial_end timestamptz;
  v_user_count integer;
  v_business_id uuid;
begin
  v_business_id:=new.business_id;
  if tg_op='UPDATE' and (old.is_active is true or new.is_active is not true) then return new; end if;
  if new.is_active is not true then return new; end if;

  perform 1 from public.businesses where id=v_business_id for update;
  if not found then raise exception 'Business workspace not found'; end if;

  select p.max_users,s.status,s.current_period_end,s.grace_until,s.trial_ends_at
    into v_max_users,v_status,v_period_end,v_grace_until,v_trial_end
    from public.business_subscriptions s
    join public.subscription_plans p on p.code=s.plan_code and p.is_active=true
   where s.business_id=v_business_id
   for update of s;

  if not found then return new; end if;

  if not (
    (v_status='active' and (v_period_end is null or v_period_end>now()))
    or (v_status='trial' and (v_trial_end is null or v_trial_end>now()))
    or (v_status='grace_period' and v_grace_until is not null and v_grace_until>now())
  ) then
    raise exception 'An active subscription or valid grace period is required before adding another user. Open Plans & Billing to renew.';
  end if;

  select count(*)::integer into v_user_count
    from public.business_members
   where business_id=v_business_id and is_active=true
     and user_id<>new.user_id;
  if v_user_count>=v_max_users then
    raise exception 'Your subscription allows a maximum of % active user(s), including the business owner. Upgrade your plan in Plans & Billing to add another user.',v_max_users;
  end if;
  return new;
end;
$$;

revoke all on function public.process_subscription_expirations() from public,anon,authenticated;
revoke all on function public.get_business_subscription_access(uuid) from public,anon;
grant execute on function public.get_business_subscription_access(uuid) to authenticated;
grant execute on function public.process_subscription_expirations() to service_role;

-- Schedule daily expiry processing when Supabase Cron is available.
do $cron$
begin
  begin
    create extension if not exists pg_cron with schema pg_catalog;
  exception when others then
    raise notice 'pg_cron could not be enabled automatically. Expiry processing will still run when a signed-in workspace checks its subscription.';
  end;
  if to_regnamespace('cron') is not null then
    begin
      execute 'select cron.schedule($1,$2,$3)'
        using 'white-lion-subscription-expiry','5 0 * * *',
              'select public.process_subscription_expirations()';
    exception when others then
      raise notice 'Could not schedule the daily expiry job automatically. Enable Supabase Cron and schedule public.process_subscription_expirations() daily.';
    end;
  end if;
end;
$cron$;

commit;
