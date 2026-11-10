-- White Lion SME Business OS — new platform registration notifications
-- Run after migrations 001–027. Safe to rerun.
begin;

create table if not exists public.platform_registration_notifications (
  id bigint generated always as identity primary key,
  user_id uuid not null unique references auth.users(id) on delete cascade,
  email text not null,
  full_name text not null default '',
  registered_at timestamptz not null default now(),
  email_confirmed_at timestamptz,
  viewed_at timestamptz
);

alter table public.platform_registration_notifications enable row level security;
revoke all on public.platform_registration_notifications from anon, authenticated;

create or replace function public.capture_platform_registration()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  insert into public.platform_registration_notifications
    (user_id, email, full_name, registered_at, email_confirmed_at)
  values (
    new.id,
    lower(coalesce(new.email, '')),
    coalesce(new.raw_user_meta_data ->> 'full_name', ''),
    coalesce(new.created_at, now()),
    new.email_confirmed_at
  )
  on conflict (user_id) do update
    set email = excluded.email,
        full_name = excluded.full_name,
        email_confirmed_at = excluded.email_confirmed_at;
  return new;
end;
$$;

drop trigger if exists capture_platform_registration on auth.users;
create trigger capture_platform_registration
after insert or update of email, email_confirmed_at on auth.users
for each row execute function public.capture_platform_registration();

-- Backfill accounts that registered before this feature was installed.
insert into public.platform_registration_notifications
  (user_id, email, full_name, registered_at, email_confirmed_at, viewed_at)
select u.id, lower(coalesce(u.email, '')),
       coalesce(u.raw_user_meta_data ->> 'full_name', ''),
       coalesce(u.created_at, now()), u.email_confirmed_at, now()
from auth.users u
on conflict (user_id) do update
  set email = excluded.email,
      full_name = excluded.full_name,
      email_confirmed_at = excluded.email_confirmed_at,
      viewed_at = coalesce(public.platform_registration_notifications.viewed_at, now());

create or replace function public.get_platform_registrations(p_limit integer default 100)
returns table (
  user_id uuid,
  email text,
  full_name text,
  registered_at timestamptz,
  email_confirmed_at timestamptz,
  viewed_at timestamptz
)
language plpgsql
stable
security definer
set search_path = ''
as $$
begin
  if not public.is_platform_developer() then
    raise exception 'Developer access required';
  end if;
  return query
    select n.user_id, n.email, n.full_name, n.registered_at,
           n.email_confirmed_at, n.viewed_at
    from public.platform_registration_notifications n
    order by n.registered_at desc
    limit greatest(1, least(coalesce(p_limit, 100), 500));
end;
$$;

create or replace function public.mark_platform_registrations_viewed()
returns integer
language plpgsql
security definer
set search_path = ''
as $$
declare v_count integer;
begin
  if not public.is_platform_developer() then
    raise exception 'Developer access required';
  end if;
  update public.platform_registration_notifications
  set viewed_at = now()
  where viewed_at is null;
  get diagnostics v_count = row_count;
  return v_count;
end;
$$;

revoke all on function public.get_platform_registrations(integer) from public;
revoke all on function public.mark_platform_registrations_viewed() from public;
grant execute on function public.get_platform_registrations(integer) to authenticated;
grant execute on function public.mark_platform_registrations_viewed() to authenticated;

commit;
