-- White Lion SME Business OS — private platform developer controls
-- Run once in Supabase SQL Editor after migrations 001 and 002.
begin;

create table if not exists public.platform_developer_emails (
  email text primary key check (email = lower(trim(email))),
  created_at timestamptz not null default now()
);
alter table public.platform_developer_emails enable row level security;
revoke all on public.platform_developer_emails from anon, authenticated;

-- The email is checked against the verified Supabase Auth JWT.
insert into public.platform_developer_emails(email)
values ('koromaalhaji0@gmail.com')
on conflict (email) do nothing;

create or replace function public.is_platform_developer()
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select exists (
    select 1
    from public.platform_developer_emails d
    where d.email = lower(coalesce(auth.jwt() ->> 'email', ''))
  );
$$;
revoke all on function public.is_platform_developer() from public;
grant execute on function public.is_platform_developer() to authenticated;

alter table public.businesses
  add column if not exists is_suspended boolean not null default false;

create table if not exists public.platform_settings (
  setting_key text primary key,
  setting_value jsonb not null default '{}'::jsonb,
  updated_by uuid references auth.users(id),
  updated_at timestamptz not null default now()
);
alter table public.platform_settings enable row level security;
drop policy if exists platform_settings_developer_only on public.platform_settings;
create policy platform_settings_developer_only
on public.platform_settings for all to authenticated
using (public.is_platform_developer())
with check (public.is_platform_developer());
grant select, insert, update, delete on public.platform_settings to authenticated;

insert into public.platform_settings(setting_key, setting_value)
values ('maintenance_mode', '{"enabled": false, "message": "The platform is temporarily undergoing maintenance."}'::jsonb)
on conflict (setting_key) do nothing;

create or replace function public.get_platform_dashboard()
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_result jsonb;
begin
  if not public.is_platform_developer() then
    raise exception 'Developer access required';
  end if;

  select jsonb_build_object(
    'business_count', (select count(*) from public.businesses),
    'suspended_count', (select count(*) from public.businesses where is_suspended),
    'user_count', (select count(*) from auth.users),
    'maintenance', coalesce((select setting_value from public.platform_settings where setting_key='maintenance_mode'), '{"enabled":false}'::jsonb),
    'businesses', coalesce((
      select jsonb_agg(jsonb_build_object(
        'id', b.id,
        'name', b.name,
        'industry', b.industry,
        'currency_code', b.currency_code,
        'owner_email', u.email,
        'is_suspended', b.is_suspended,
        'created_at', b.created_at,
        'member_count', (select count(*) from public.business_members m where m.business_id=b.id)
      ) order by b.created_at desc)
      from public.businesses b
      left join auth.users u on u.id=b.owner_user_id
    ), '[]'::jsonb)
  ) into v_result;
  return v_result;
end;
$$;
revoke all on function public.get_platform_dashboard() from public;
grant execute on function public.get_platform_dashboard() to authenticated;

create or replace function public.set_platform_business_suspension(
  p_business_id uuid,
  p_is_suspended boolean
)
returns void
language plpgsql
security definer
set search_path = ''
as $$
begin
  if not public.is_platform_developer() then
    raise exception 'Developer access required';
  end if;
  update public.businesses
  set is_suspended=p_is_suspended, updated_at=now()
  where id=p_business_id;
  if not found then raise exception 'Business not found'; end if;
  insert into public.audit_logs(business_id, actor_user_id, action, entity_table, entity_id, details)
  values (p_business_id, auth.uid(), case when p_is_suspended then 'platform_business_suspended' else 'platform_business_restored' end,
          'businesses', p_business_id::text, jsonb_build_object('is_suspended',p_is_suspended));
end;
$$;
revoke all on function public.set_platform_business_suspension(uuid,boolean) from public;
grant execute on function public.set_platform_business_suspension(uuid,boolean) to authenticated;

create or replace function public.set_platform_maintenance(
  p_enabled boolean,
  p_message text default 'The platform is temporarily undergoing maintenance.'
)
returns void
language plpgsql
security definer
set search_path = ''
as $$
begin
  if not public.is_platform_developer() then
    raise exception 'Developer access required';
  end if;
  insert into public.platform_settings(setting_key,setting_value,updated_by,updated_at)
  values ('maintenance_mode',jsonb_build_object(
    'enabled',p_enabled,
    'message',coalesce(nullif(trim(p_message),''),'The platform is temporarily undergoing maintenance.')
  ),auth.uid(),now())
  on conflict (setting_key) do update
  set setting_value=excluded.setting_value,updated_by=excluded.updated_by,updated_at=now();
end;
$$;
revoke all on function public.set_platform_maintenance(boolean,text) from public;
grant execute on function public.set_platform_maintenance(boolean,text) to authenticated;

create or replace function public.set_platform_member_access(
  p_business_id uuid,
  p_email text,
  p_role public.business_role,
  p_is_active boolean
)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_user_id uuid;
begin
  if not public.is_platform_developer() then
    raise exception 'Developer access required';
  end if;
  select id into v_user_id from auth.users where lower(email)=lower(trim(p_email));
  if v_user_id is null then raise exception 'No registered account found for that email'; end if;
  if p_role='owner' then raise exception 'Owner role changes require a separate transfer process'; end if;

  insert into public.business_members(business_id,user_id,role,is_active,invited_by)
  values(p_business_id,v_user_id,p_role,p_is_active,auth.uid())
  on conflict (business_id,user_id) do update
  set role=excluded.role,is_active=excluded.is_active;

  insert into public.audit_logs(business_id,actor_user_id,action,entity_table,entity_id,details)
  values(p_business_id,auth.uid(),'platform_membership_changed','business_members',v_user_id::text,
    jsonb_build_object('email',lower(trim(p_email)),'role',p_role,'active',p_is_active));
end;
$$;
revoke all on function public.set_platform_member_access(uuid,text,public.business_role,boolean) from public;
grant execute on function public.set_platform_member_access(uuid,text,public.business_role,boolean) to authenticated;

commit;
