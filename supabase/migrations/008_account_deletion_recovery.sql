-- White Lion SME OS — 30-day account deletion and recovery workflow
-- Run after migrations 001–007. Permanent Auth deletion is handled only by the Edge Function.
begin;

alter table public.platform_audit_logs
  add column if not exists actor_email_snapshot text;

-- Preserve operational and audit records when a non-owner account is permanently removed.
-- Business owners are blocked from deletion requests until ownership is transferred.
do $$
declare r record; v_column text;
begin
  for r in
    select c.conname, c.conrelid::regclass as table_name,
           a.attname as column_name
    from pg_constraint c
    join unnest(c.conkey) with ordinality k(attnum, ord) on true
    join pg_attribute a on a.attrelid=c.conrelid and a.attnum=k.attnum
    where c.contype='f'
      and c.confrelid='auth.users'::regclass
      and c.conrelid in (
        'public.businesses'::regclass,
        'public.business_members'::regclass,
        'public.sales'::regclass,
        'public.purchases'::regclass,
        'public.inventory_movements'::regclass,
        'public.expenses'::regclass,
        'public.audit_logs'::regclass
      )
      and a.attname not in ('owner_user_id','user_id')
  loop
    execute format('alter table %s alter column %I drop not null',r.table_name,r.column_name);
    execute format('alter table %s drop constraint %I',r.table_name,r.conname);
    execute format('alter table %s add constraint %I foreign key (%I) references auth.users(id) on delete set null',
      r.table_name,r.conname,r.column_name);
  end loop;
end $$;

create table if not exists public.platform_account_deletion_requests (
  id uuid primary key default gen_random_uuid(),
  target_user_id uuid not null,
  target_email text not null,
  requested_by uuid not null references auth.users(id),
  requested_at timestamptz not null default now(),
  scheduled_for timestamptz not null default (now() + interval '30 days'),
  previous_is_active boolean not null default true,
  status text not null default 'pending'
    check (status in ('pending','cancelled','completed','failed')),
  cancelled_at timestamptz,
  completed_at timestamptz,
  failure_note text,
  created_at timestamptz not null default now()
);
create index if not exists platform_deletion_pending_due_idx
  on public.platform_account_deletion_requests(scheduled_for)
  where status='pending';
alter table public.platform_account_deletion_requests enable row level security;
revoke all on public.platform_account_deletion_requests from public, anon, authenticated;

create or replace function public.request_platform_account_deletion(
  p_user_id uuid,
  p_confirm_email text
) returns uuid
language plpgsql security definer
set search_path=''
as $$
declare v_email text; v_previous boolean; v_request_id uuid;
begin
  if not public.is_platform_developer() then raise exception 'Developer access required'; end if;
  if p_user_id=auth.uid() then raise exception 'You cannot request deletion of your own developer account'; end if;
  select lower(email) into v_email from auth.users where id=p_user_id;
  if v_email is null then raise exception 'Account not found'; end if;
  if lower(trim(coalesce(p_confirm_email,''))) <> v_email then
    raise exception 'The confirmation email does not match this account';
  end if;
  if exists(select 1 from public.platform_developer_emails where lower(email)=v_email) then
    raise exception 'Platform developer accounts are protected from deletion';
  end if;
  if exists(select 1 from public.businesses where owner_user_id=p_user_id) then
    raise exception 'This account owns a business workspace. Transfer ownership before requesting deletion.';
  end if;
  if exists(select 1 from public.platform_account_deletion_requests
            where target_user_id=p_user_id and status='pending') then
    raise exception 'A deletion request is already pending for this account';
  end if;
  select coalesce(is_active,true) into v_previous
    from public.platform_account_access where user_id=p_user_id;
  v_previous := coalesce(v_previous,true);

  insert into public.platform_account_deletion_requests(
    target_user_id,target_email,requested_by,previous_is_active
  ) values(p_user_id,v_email,auth.uid(),v_previous)
  returning id into v_request_id;

  insert into public.platform_account_access(user_id,is_active,note,updated_by,updated_at)
  values(p_user_id,false,'Deletion requested; 30-day recovery period',auth.uid(),now())
  on conflict(user_id) do update set
    is_active=false,note='Deletion requested; 30-day recovery period',
    updated_by=auth.uid(),updated_at=now();

  insert into public.platform_audit_logs(actor_user_id,actor_email_snapshot,action,entity_table,entity_id,details)
  values(auth.uid(),auth.jwt()->>'email','account_deletion_requested',
    'auth.users',p_user_id::text,
    jsonb_build_object('request_id',v_request_id,'target_email',v_email,'scheduled_for',now()+interval '30 days'));
  return v_request_id;
end;
$$;

create or replace function public.get_platform_account_deletion_requests()
returns jsonb
language plpgsql stable security definer
set search_path=''
as $$
declare v_result jsonb;
begin
  if not public.is_platform_developer() then raise exception 'Developer access required'; end if;
  select coalesce(jsonb_agg(jsonb_build_object(
    'id',d.id,'target_user_id',d.target_user_id,'target_email',d.target_email,
    'requested_at',d.requested_at,'scheduled_for',d.scheduled_for,
    'previous_is_active',d.previous_is_active,'status',d.status,
    'cancelled_at',d.cancelled_at,'completed_at',d.completed_at,'failure_note',d.failure_note
  ) order by d.requested_at desc),'[]'::jsonb)
  into v_result from public.platform_account_deletion_requests d;
  return v_result;
end;
$$;

create or replace function public.cancel_platform_account_deletion(p_request_id uuid)
returns void
language plpgsql security definer
set search_path=''
as $$
declare d record; v_email text;
begin
  if not public.is_platform_developer() then raise exception 'Developer access required'; end if;
  select * into d from public.platform_account_deletion_requests
    where id=p_request_id and status='pending' for update;
  if not found then raise exception 'Pending deletion request not found'; end if;
  if d.scheduled_for <= now() then raise exception 'The 30-day recovery period has ended; this request can no longer be cancelled here'; end if;

  update public.platform_account_deletion_requests set status='cancelled',cancelled_at=now()
    where id=p_request_id;
  if exists(select 1 from auth.users where id=d.target_user_id) then
    insert into public.platform_account_access(user_id,is_active,note,updated_by,updated_at)
    values(d.target_user_id,d.previous_is_active,'',auth.uid(),now())
    on conflict(user_id) do update set
      is_active=excluded.is_active,note='',updated_by=auth.uid(),updated_at=now();
  end if;
  insert into public.platform_audit_logs(actor_user_id,actor_email_snapshot,action,entity_table,entity_id,details)
  values(auth.uid(),auth.jwt()->>'email','account_deletion_cancelled',
    'auth.users',d.target_user_id::text,jsonb_build_object('request_id',p_request_id,'target_email',d.target_email));
end;
$$;

revoke all on function public.request_platform_account_deletion(uuid,text) from public;
revoke all on function public.get_platform_account_deletion_requests() from public;
revoke all on function public.cancel_platform_account_deletion(uuid) from public;
grant execute on function public.request_platform_account_deletion(uuid,text) to authenticated;
grant execute on function public.get_platform_account_deletion_requests() to authenticated;
grant execute on function public.cancel_platform_account_deletion(uuid) to authenticated;

-- Snapshot actor email at capture time so audit history remains readable after Auth deletion.
create or replace function public.capture_platform_audit_event()
returns trigger language plpgsql security definer set search_path=''
as $$
declare v_actor_email text;
begin
  select email into v_actor_email from auth.users where id=new.actor_user_id;
  insert into public.platform_audit_logs(
    business_id,actor_user_id,actor_email_snapshot,action,entity_table,entity_id,details,occurred_at
  ) values (
    new.business_id,new.actor_user_id,v_actor_email,new.action,new.entity_table,
    new.entity_id,coalesce(new.details,'{}'::jsonb),now()
  );
  return new;
end;
$$;

create or replace function public.get_platform_audit_log(p_limit integer default 100)
returns jsonb language plpgsql stable security definer set search_path=''
as $$
declare v_result jsonb;
begin
  if not public.is_platform_developer() then raise exception 'Developer access required'; end if;
  select coalesce(jsonb_agg(row_data order by occurred_at desc),'[]'::jsonb)
  into v_result
  from (
    select jsonb_build_object(
      'id',l.id,'business_id',l.business_id,'business_name',b.name,
      'actor_user_id',l.actor_user_id,'actor_email',coalesce(l.actor_email_snapshot,u.email),
      'action',l.action,'entity_table',l.entity_table,'entity_id',l.entity_id,
      'details',l.details,'occurred_at',l.occurred_at
    ) as row_data,l.occurred_at
    from public.platform_audit_logs l
    left join public.businesses b on b.id=l.business_id
    left join auth.users u on u.id=l.actor_user_id
    order by l.occurred_at desc
    limit greatest(1,least(coalesce(p_limit,100),250))
  ) events;
  return v_result;
end;
$$;
revoke all on function public.get_platform_audit_log(integer) from public;
grant execute on function public.get_platform_audit_log(integer) to authenticated;

commit;
