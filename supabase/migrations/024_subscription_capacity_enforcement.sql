-- White Lion SME OS — Migration 024
-- Enforce subscribed plan limits at the database boundary.
-- Existing workspaces without a subscription are deliberately grandfathered:
-- this migration does not interrupt their current operations.
begin;

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
  v_branch_count integer;
begin
  if new.is_active is not true then
    return new;
  end if;

  -- Serialize capacity checks for this workspace to prevent concurrent over-allocation.
  perform 1 from public.businesses where id = new.business_id for update;
  if not found then
    raise exception 'Business workspace not found';
  end if;

  select p.max_branches, s.status, s.current_period_end
    into v_max_branches, v_status, v_period_end
  from public.business_subscriptions s
  join public.subscription_plans p on p.code = s.plan_code and p.is_active = true
  where s.business_id = new.business_id
  for update of s;

  -- No subscription yet: preserve access for existing/grandfathered workspaces.
  if not found then
    return new;
  end if;

  if v_status not in ('active','trial','grace_period')
     or (v_period_end is not null and v_period_end <= now()) then
    raise exception 'An active subscription is required before adding another branch. Open Plans & Billing to renew or activate a plan.';
  end if;

  select count(*)::integer into v_branch_count
  from public.branches
  where business_id = new.business_id and is_active = true
    and (tg_op <> 'UPDATE' or id <> new.id);

  if v_branch_count >= v_max_branches then
    raise exception 'Your subscription allows a maximum of % active branch(es). Upgrade your plan in Plans & Billing to add another branch.', v_max_branches;
  end if;

  return new;
end;
$$;

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
  v_user_count integer;
  v_business_id uuid;
begin
  v_business_id := new.business_id;

  -- Only count new activations, not ordinary edits to an existing active member.
  if tg_op = 'UPDATE' and (old.is_active is true or new.is_active is not true) then
    return new;
  end if;
  if new.is_active is not true then
    return new;
  end if;

  -- Serialize member-capacity checks for this workspace.
  perform 1 from public.businesses where id = v_business_id for update;
  if not found then
    raise exception 'Business workspace not found';
  end if;

  select p.max_users, s.status, s.current_period_end
    into v_max_users, v_status, v_period_end
  from public.business_subscriptions s
  join public.subscription_plans p on p.code = s.plan_code and p.is_active = true
  where s.business_id = v_business_id
  for update of s;

  -- No subscription yet: preserve access for existing/grandfathered workspaces.
  if not found then
    return new;
  end if;

  if v_status not in ('active','trial','grace_period')
     or (v_period_end is not null and v_period_end <= now()) then
    raise exception 'An active subscription is required before adding another user. Open Plans & Billing to renew or activate a plan.';
  end if;

  select count(*)::integer into v_user_count
  from public.business_members
  where business_id = v_business_id and is_active = true
    and user_id <> new.user_id;

  if v_user_count >= v_max_users then
    raise exception 'Your subscription allows a maximum of % active user(s), including the business owner. Upgrade your plan in Plans & Billing to add another user.', v_max_users;
  end if;

  return new;
end;
$$;

drop trigger if exists enforce_subscription_branch_capacity on public.branches;
create trigger enforce_subscription_branch_capacity
before insert or update of is_active on public.branches
for each row execute function public.enforce_business_branch_capacity();

drop trigger if exists enforce_subscription_user_capacity on public.business_members;
create trigger enforce_subscription_user_capacity
before insert or update of is_active on public.business_members
for each row execute function public.enforce_business_user_capacity();

revoke all on function public.enforce_business_branch_capacity() from public, anon, authenticated;
revoke all on function public.enforce_business_user_capacity() from public, anon, authenticated;

commit;
