-- White Lion SME OS — separate new-business registration notifications.
-- Run after migration 028. Existing workspaces are backfilled as already reviewed.
begin;

create table if not exists public.platform_business_registration_notifications (
  id bigint generated always as identity primary key,
  business_id uuid not null unique references public.businesses(id) on delete cascade,
  owner_user_id uuid not null references auth.users(id) on delete cascade,
  business_name text not null,
  industry text not null default 'Multi-industry',
  owner_email text not null default '',
  registered_at timestamptz not null default now(),
  viewed_at timestamptz
);

alter table public.platform_business_registration_notifications enable row level security;
revoke all on public.platform_business_registration_notifications from anon, authenticated;

create or replace function public.capture_platform_business_registration()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_email text;
begin
  select lower(coalesce(u.email, '')) into v_email
  from auth.users u where u.id = new.owner_user_id;

  insert into public.platform_business_registration_notifications
    (business_id, owner_user_id, business_name, industry, owner_email, registered_at)
  values
    (new.id, new.owner_user_id, new.name, coalesce(new.industry, 'Multi-industry'),
     coalesce(v_email, ''), coalesce(new.created_at, now()))
  on conflict (business_id) do update
    set business_name = excluded.business_name,
        industry = excluded.industry,
        owner_email = excluded.owner_email;
  return new;
end;
$$;

drop trigger if exists capture_platform_business_registration on public.businesses;
create trigger capture_platform_business_registration
after insert on public.businesses
for each row execute function public.capture_platform_business_registration();

-- Do not present workspaces created before this feature as new registrations.
insert into public.platform_business_registration_notifications
  (business_id, owner_user_id, business_name, industry, owner_email, registered_at, viewed_at)
select b.id, b.owner_user_id, b.name, coalesce(b.industry, 'Multi-industry'),
       lower(coalesce(u.email, '')), coalesce(b.created_at, now()), now()
from public.businesses b
left join auth.users u on u.id = b.owner_user_id
on conflict (business_id) do update
  set business_name = excluded.business_name,
      industry = excluded.industry,
      owner_email = excluded.owner_email,
      viewed_at = coalesce(public.platform_business_registration_notifications.viewed_at, now());

create or replace function public.get_platform_business_registrations(p_limit integer default 100)
returns table (
  business_id uuid,
  business_name text,
  industry text,
  owner_user_id uuid,
  owner_email text,
  registered_at timestamptz,
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
    select n.business_id, n.business_name, n.industry, n.owner_user_id,
           n.owner_email, n.registered_at, n.viewed_at
    from public.platform_business_registration_notifications n
    order by n.registered_at desc
    limit greatest(1, least(coalesce(p_limit, 100), 500));
end;
$$;

create or replace function public.mark_platform_business_registrations_viewed()
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
  update public.platform_business_registration_notifications
  set viewed_at = now()
  where viewed_at is null;
  get diagnostics v_count = row_count;
  return v_count;
end;
$$;

revoke all on function public.get_platform_business_registrations(integer) from public;
revoke all on function public.mark_platform_business_registrations_viewed() from public;
grant execute on function public.get_platform_business_registrations(integer) to authenticated;
grant execute on function public.mark_platform_business_registrations_viewed() to authenticated;

commit;
