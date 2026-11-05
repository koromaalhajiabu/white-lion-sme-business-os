
begin;

-- 1. Remove direct membership writes.
drop policy if exists "members_manage_admin"
on public.business_members;

revoke insert, update, delete
on public.business_members from authenticated;

grant select
on public.business_members to authenticated;

-- 2. Secure membership-management function.
create or replace function public.manage_business_member(
  p_business_id uuid,
  p_user_id uuid,
  p_role public.business_role,
  p_is_active boolean
)
returns void
language plpgsql
security definer
set search_path = public, auth
as $$
declare
  v_actor_role public.business_role;
  v_target_role public.business_role;
begin
  if auth.uid() is null then
    raise exception 'Authentication required';
  end if;

  if p_user_id = auth.uid() then
    raise exception 'You cannot modify your own membership';
  end if;

  select role into v_actor_role
  from public.business_members
  where business_id = p_business_id
    and user_id = auth.uid()
    and is_active = true;

  if v_actor_role is null
     or v_actor_role not in ('owner', 'admin') then
    raise exception 'Not authorised';
  end if;

  select role into v_target_role
  from public.business_members
  where business_id = p_business_id
    and user_id = p_user_id;

  if v_target_role = 'owner' then
    raise exception 'The owner membership cannot be changed here';
  end if;

  if v_actor_role = 'admin'
     and p_role in ('owner', 'admin') then
    raise exception 'Administrators cannot grant privileged roles';
  end if;

  if p_role = 'owner' then
    raise exception 'Owner transfer requires a separate controlled process';
  end if;

  insert into public.business_members (
    business_id,
    user_id,
    role,
    is_active,
    invited_by
  )
  values (
    p_business_id,
    p_user_id,
    p_role,
    p_is_active,
    auth.uid()
  )
  on conflict (business_id, user_id)
  do update set
    role = excluded.role,
    is_active = excluded.is_active;

  insert into public.audit_logs (
    business_id,
    actor_user_id,
    action,
    entity_table,
    entity_id,
    details
  )
  values (
    p_business_id,
    auth.uid(),
    'membership_changed',
    'business_members',
    p_user_id::text,
    jsonb_build_object(
      'role', p_role,
      'active', p_is_active
    )
  );
end;
$$;

revoke all on function public.manage_business_member(
  uuid, uuid, public.business_role, boolean
) from public;

grant execute on function public.manage_business_member(
  uuid, uuid, public.business_role, boolean
) to authenticated;

-- 3. Business-specific industry modules.
create table if not exists public.business_industry_modules (
  business_id uuid not null
    references public.businesses(id) on delete cascade,

  module_key text not null,
  is_enabled boolean not null default false,
  configuration jsonb not null default '{}'::jsonb,

  updated_by uuid references auth.users(id),
  updated_at timestamptz not null default now(),

  primary key (business_id, module_key)
);

alter table public.business_industry_modules
enable row level security;

drop policy if exists "modules_member_read"
on public.business_industry_modules;

drop policy if exists "modules_admin_manage"
on public.business_industry_modules;

create policy "modules_member_read"
on public.business_industry_modules
for select to authenticated
using (public.is_business_member(business_id));

create policy "modules_admin_manage"
on public.business_industry_modules
for all to authenticated
using (
  public.has_business_role(
    business_id,
    array['owner','admin']::public.business_role[]
  )
)
with check (
  public.has_business_role(
    business_id,
    array['owner','admin']::public.business_role[]
  )
);

-- 4. Seed the module catalogue for every new business.
create or replace function public.seed_business_modules()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  v_module text;
begin
  foreach v_module in array array[
    'core',
    'sales_pos',
    'inventory',
    'purchasing',
    'customers',
    'suppliers',
    'expenses',
    'employees',
    'accounting',
    'pharmacy',
    'restaurant',
    'school',
    'healthcare',
    'transport',
    'services',
    'manufacturing',
    'property',
    'fleet',
    'appointments',
    'projects',
    'compliance'
  ]
  loop
    insert into public.business_industry_modules (
      business_id,
      module_key,
      is_enabled
    )
    values (
      new.id,
      v_module,
      v_module = 'core'
    )
    on conflict (business_id, module_key) do nothing;
  end loop;

  return new;
end;
$$;

drop trigger if exists business_module_seed
on public.businesses;

create trigger business_module_seed
after insert on public.businesses
for each row
execute function public.seed_business_modules();

-- 5. Backfill existing businesses.
do $$
declare
  v_business record;
begin
  for v_business in
    select id from public.businesses
  loop
    insert into public.business_industry_modules (
      business_id,
      module_key,
      is_enabled
    )
    select
      v_business.id,
      module_name,
      module_name = 'core'
    from unnest(array[
      'core',
      'sales_pos',
      'inventory',
      'purchasing',
      'customers',
      'suppliers',
      'expenses',
      'employees',
      'accounting',
      'pharmacy',
      'restaurant',
      'school',
      'healthcare',
      'transport',
      'services',
      'manufacturing',
      'property',
      'fleet',
      'appointments',
      'projects',
      'compliance'
    ]) as module_name
    on conflict (business_id, module_key) do nothing;
  end loop;
end;
$$;

commit;
