-- White Lion SME Business OS — platform-wide account access controls
-- Run once in Supabase SQL Editor after migrations 001–005.
begin;

create table if not exists public.platform_account_access (
  user_id uuid primary key references auth.users(id) on delete cascade,
  is_active boolean not null default true,
  note text not null default '',
  updated_by uuid references auth.users(id),
  updated_at timestamptz not null default now()
);
alter table public.platform_account_access enable row level security;
revoke all on public.platform_account_access from anon, authenticated;

-- Platform account suspension blocks workspace access while preserving the Auth account and its data.
create or replace function public.is_business_member(p_business_id uuid)
returns boolean
language sql stable security definer
set search_path = ''
as $$
  select
    coalesce((select a.is_active from public.platform_account_access a where a.user_id=auth.uid()), true)
    and (
      public.is_platform_developer()
      or coalesce((
        select not (s.setting_value ->> 'enabled')::boolean
        from public.platform_settings s
        where s.setting_key='maintenance_mode'
      ), true)
    )
    and exists (
      select 1
      from public.business_members m
      join public.businesses b on b.id=m.business_id
      where m.business_id=p_business_id
        and m.user_id=auth.uid()
        and m.is_active=true
        and b.is_suspended=false
    );
$$;

create or replace function public.has_business_role(
  p_business_id uuid,
  p_roles public.business_role[]
)
returns boolean
language sql stable security definer
set search_path = ''
as $$
  select
    coalesce((select a.is_active from public.platform_account_access a where a.user_id=auth.uid()), true)
    and (
      public.is_platform_developer()
      or coalesce((
        select not (s.setting_value ->> 'enabled')::boolean
        from public.platform_settings s
        where s.setting_key='maintenance_mode'
      ), true)
    )
    and exists (
      select 1
      from public.business_members m
      join public.businesses b on b.id=m.business_id
      where m.business_id=p_business_id
        and m.user_id=auth.uid()
        and m.is_active=true
        and b.is_suspended=false
        and m.role=any(p_roles)
    );
$$;
revoke all on function public.is_business_member(uuid) from public;
revoke all on function public.has_business_role(uuid,public.business_role[]) from public;
grant execute on function public.is_business_member(uuid) to authenticated;
grant execute on function public.has_business_role(uuid,public.business_role[]) to authenticated;

create or replace function public.get_platform_accounts()
returns jsonb
language plpgsql stable security definer
set search_path = ''
as $$
declare v_result jsonb;
begin
  if not public.is_platform_developer() then raise exception 'Developer access required'; end if;
  select coalesce(jsonb_agg(jsonb_build_object(
    'user_id',u.id,
    'email',u.email,
    'full_name',coalesce(nullif(p.full_name,''),u.raw_user_meta_data->>'full_name',''),
    'created_at',u.created_at,
    'last_sign_in_at',u.last_sign_in_at,
    'email_confirmed',u.email_confirmed_at is not null,
    'is_active',coalesce(a.is_active,true),
    'note',coalesce(a.note,''),
    'business_count',(select count(*) from public.business_members m where m.user_id=u.id)
  ) order by u.created_at desc),'[]'::jsonb)
  into v_result
  from auth.users u
  left join public.profiles p on p.id=u.id
  left join public.platform_account_access a on a.user_id=u.id;
  return v_result;
end;
$$;
revoke all on function public.get_platform_accounts() from public;
grant execute on function public.get_platform_accounts() to authenticated;

create or replace function public.set_platform_account_access(
  p_user_id uuid,
  p_is_active boolean,
  p_note text default ''
)
returns void
language plpgsql security definer
set search_path = ''
as $$
declare v_email text;
begin
  if not public.is_platform_developer() then raise exception 'Developer access required'; end if;
  if p_user_id=auth.uid() then raise exception 'You cannot suspend your own developer account'; end if;
  select email into v_email from auth.users where id=p_user_id;
  if v_email is null then raise exception 'Account not found'; end if;
  if exists(select 1 from public.platform_developer_emails where email=lower(v_email)) then
    raise exception 'Platform developer accounts cannot be suspended from this console';
  end if;
  insert into public.platform_account_access(user_id,is_active,note,updated_by,updated_at)
  values(p_user_id,p_is_active,coalesce(nullif(trim(p_note),''),''),auth.uid(),now())
  on conflict(user_id) do update set
    is_active=excluded.is_active,
    note=excluded.note,
    updated_by=excluded.updated_by,
    updated_at=now();

  insert into public.audit_logs(business_id,actor_user_id,action,entity_table,entity_id,details)
  select m.business_id,auth.uid(),
    case when p_is_active then 'platform_account_restored' else 'platform_account_suspended' end,
    'auth.users',p_user_id::text,
    jsonb_build_object('email',lower(v_email),'is_active',p_is_active,'note',coalesce(p_note,''))
  from public.business_members m where m.user_id=p_user_id;
end;
$$;
revoke all on function public.set_platform_account_access(uuid,boolean,text) from public;
grant execute on function public.set_platform_account_access(uuid,boolean,text) to authenticated;

commit;
