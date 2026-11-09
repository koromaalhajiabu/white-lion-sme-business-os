-- White Lion SME Business OS — Migration 026
-- Automatically start a seven-day Professional trial for every newly registered business.
-- Existing businesses and subscriptions are preserved; no invoices or payments are created.
begin;

create or replace function public.start_new_business_trial()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_trial_start timestamptz := now();
  v_trial_end timestamptz := now() + interval '7 days';
begin
  -- The Professional plan must exist and be active before a trial can be issued.
  if not exists (
    select 1
      from public.subscription_plans
     where code = 'professional'
       and is_active = true
  ) then
    raise exception 'The Professional plan is unavailable; business trial could not be started';
  end if;

  insert into public.business_subscriptions (
    business_id,
    plan_code,
    status,
    currency_code,
    billing_cycle,
    current_period_start,
    current_period_end,
    trial_ends_at,
    grace_until,
    updated_at
  )
  values (
    new.id,
    'professional',
    'trial',
    new.currency_code,
    'monthly',
    v_trial_start,
    v_trial_end,
    v_trial_end,
    null,
    v_trial_start
  )
  on conflict (business_id) do nothing;

  insert into public.subscription_events (
    business_id,
    actor_user_id,
    event_type,
    details
  )
  values (
    new.id,
    auth.uid(),
    'free_trial_started',
    jsonb_build_object(
      'plan_code', 'professional',
      'trial_days', 7,
      'trial_started_at', v_trial_start,
      'trial_ends_at', v_trial_end,
      'payment_required_at_signup', false
    )
  );

  return new;
end;
$$;

drop trigger if exists start_business_free_trial on public.businesses;
create trigger start_business_free_trial
after insert on public.businesses
for each row
execute function public.start_new_business_trial();

revoke all on function public.start_new_business_trial() from public, anon, authenticated;

commit;
