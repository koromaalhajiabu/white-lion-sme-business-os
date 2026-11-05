begin;

-- Central, developer-only copy of all business audit events.
create table if not exists public.platform_audit_logs (
  id bigint generated always as identity primary key,
  business_id uuid,
  actor_user_id uuid,
  action text not null,
  entity_table text,
  entity_id text,
  details jsonb not null default '{}'::jsonb,
  occurred_at timestamptz not null default now()
);

alter table public.platform_audit_logs enable row level security;
revoke all on public.platform_audit_logs from anon, authenticated;
revoke all on public.platform_audit_logs from public;

create or replace function public.capture_platform_audit_event()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  insert into public.platform_audit_logs(
    business_id, actor_user_id, action, entity_table, entity_id, details, occurred_at
  ) values (
    new.business_id, new.actor_user_id, new.action, new.entity_table,
    new.entity_id, coalesce(new.details, '{}'::jsonb), now()
  );
  return new;
end;
$$;

drop trigger if exists platform_audit_capture on public.audit_logs;
create trigger platform_audit_capture
after insert on public.audit_logs
for each row execute function public.capture_platform_audit_event();

create or replace function public.get_platform_audit_log(p_limit integer default 100)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare v_result jsonb;
begin
  if not public.is_platform_developer() then
    raise exception 'Developer access required';
  end if;

  select coalesce(jsonb_agg(row_data order by occurred_at desc), '[]'::jsonb)
  into v_result
  from (
    select
      jsonb_build_object(
        'id', l.id,
        'business_id', l.business_id,
        'business_name', b.name,
        'actor_user_id', l.actor_user_id,
        'actor_email', u.email,
        'action', l.action,
        'entity_table', l.entity_table,
        'entity_id', l.entity_id,
        'details', l.details,
        'occurred_at', l.occurred_at
      ) as row_data,
      l.occurred_at
    from public.platform_audit_logs l
    left join public.businesses b on b.id = l.business_id
    left join auth.users u on u.id = l.actor_user_id
    order by l.occurred_at desc
    limit greatest(1, least(coalesce(p_limit,100),250))
  ) events;

  return v_result;
end;
$$;

revoke all on function public.get_platform_audit_log(integer) from public;
grant execute on function public.get_platform_audit_log(integer) to authenticated;

commit;
