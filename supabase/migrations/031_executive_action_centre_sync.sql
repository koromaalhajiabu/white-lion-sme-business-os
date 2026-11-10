-- White Lion SME OS — Executive Action Centre cloud synchronization
-- Migration 031. Safe to run once in the existing Supabase project.
begin;

create table if not exists public.executive_actions (
  id uuid primary key default gen_random_uuid(),
  business_id uuid not null references public.businesses(id) on delete cascade,
  branch_id uuid null,
  client_id text not null,
  kind text not null default 'task' check (kind in ('task','alert')),
  action_type text not null default 'Management task',
  title text not null check (length(trim(title)) between 1 and 160),
  detail text not null default '',
  priority text not null default 'Normal' check (priority in ('Normal','High','Urgent')),
  status text not null default 'Open' check (status in ('Open','Acknowledged','Resolved','Completed')),
  assignee_user_id uuid null references auth.users(id) on delete set null,
  assignee_label text not null default '',
  due_date date null,
  payload jsonb not null default '{}'::jsonb,
  created_by uuid not null default auth.uid() references auth.users(id),
  updated_by uuid not null default auth.uid() references auth.users(id),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint executive_actions_branch_business_fkey
    foreign key (branch_id,business_id)
    references public.branches(id,business_id) on delete set null (branch_id),
  constraint executive_actions_business_client_unique unique (business_id,client_id),
  constraint executive_actions_id_business_unique unique (id,business_id)
);

create index if not exists executive_actions_business_branch_updated_idx
  on public.executive_actions(business_id,branch_id,updated_at desc);
create index if not exists executive_actions_assignee_status_idx
  on public.executive_actions(assignee_user_id,status,updated_at desc);

alter table public.executive_actions enable row level security;
revoke all on public.executive_actions from anon;
grant select,insert,update,delete on public.executive_actions to authenticated;

drop policy if exists executive_actions_member_read on public.executive_actions;
create policy executive_actions_member_read on public.executive_actions
for select to authenticated
using (
  public.is_business_member(business_id)
  and (
    branch_id is null
    or public.has_business_role(business_id,array['owner','admin','manager']::public.business_role[])
    or exists (
      select 1 from public.branch_members bm
      where bm.business_id=executive_actions.business_id
        and bm.branch_id=executive_actions.branch_id
        and bm.user_id=auth.uid()
        and bm.is_active
    )
  )
);

drop policy if exists executive_actions_manager_insert on public.executive_actions;
create policy executive_actions_manager_insert on public.executive_actions
for insert to authenticated
with check (
  created_by=auth.uid()
  and updated_by=auth.uid()
  and public.has_business_role(business_id,array['owner','admin','manager']::public.business_role[])
);

drop policy if exists executive_actions_manager_or_assignee_update on public.executive_actions;
create policy executive_actions_manager_or_assignee_update on public.executive_actions
for update to authenticated
using (
  public.is_business_member(business_id)
  and (
    public.has_business_role(business_id,array['owner','admin','manager']::public.business_role[])
    or assignee_user_id=auth.uid()
  )
  and (
    branch_id is null
    or public.has_business_role(business_id,array['owner','admin','manager']::public.business_role[])
    or exists (
      select 1 from public.branch_members bm
      where bm.business_id=executive_actions.business_id
        and bm.branch_id=executive_actions.branch_id
        and bm.user_id=auth.uid()
        and bm.is_active
    )
  )
)
with check (
  public.is_business_member(business_id)
  and (
    public.has_business_role(business_id,array['owner','admin','manager']::public.business_role[])
    or assignee_user_id=auth.uid()
  )
);

drop policy if exists executive_actions_manager_delete on public.executive_actions;
create policy executive_actions_manager_delete on public.executive_actions
for delete to authenticated
using (public.has_business_role(business_id,array['owner','admin','manager']::public.business_role[]));

-- Assigned staff can update status only; managers retain full action-management access.
create or replace function public.guard_executive_action_assignee_update()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  if not public.has_business_role(old.business_id,array['owner','admin','manager']::public.business_role[]) then
    if old.assignee_user_id is distinct from auth.uid() then
      raise exception 'Only the assigned employee or a manager can update this action';
    end if;
    if (to_jsonb(new) - array['status','updated_at','updated_by'])
       is distinct from
       (to_jsonb(old) - array['status','updated_at','updated_by']) then
      raise exception 'Assigned employees may update action status only';
    end if;
  end if;
  new.updated_by := auth.uid();
  new.updated_at := now();
  return new;
end;
$$;

drop trigger if exists executive_actions_assignee_guard on public.executive_actions;
create trigger executive_actions_assignee_guard
before update on public.executive_actions
for each row execute function public.guard_executive_action_assignee_update();

create table if not exists public.executive_action_events (
  id uuid primary key default gen_random_uuid(),
  business_id uuid not null references public.businesses(id) on delete cascade,
  action_id uuid not null,
  client_event_id text not null,
  actor_user_id uuid not null default auth.uid() references auth.users(id),
  event text not null check (length(trim(event)) between 1 and 240),
  details jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now(),
  constraint executive_action_events_action_business_fkey
    foreign key (action_id,business_id)
    references public.executive_actions(id,business_id) on delete cascade,
  constraint executive_action_events_business_client_unique
    unique (business_id,client_event_id)
);

create index if not exists executive_action_events_business_created_idx
  on public.executive_action_events(business_id,created_at desc);
create index if not exists executive_action_events_action_created_idx
  on public.executive_action_events(action_id,created_at desc);

alter table public.executive_action_events enable row level security;
revoke all on public.executive_action_events from anon;
grant select,insert on public.executive_action_events to authenticated;

drop policy if exists executive_action_events_member_read on public.executive_action_events;
create policy executive_action_events_member_read on public.executive_action_events
for select to authenticated
using (
  public.is_business_member(business_id)
  and exists (
    select 1 from public.executive_actions a
    where a.id=executive_action_events.action_id
      and a.business_id=executive_action_events.business_id
  )
);

drop policy if exists executive_action_events_actor_insert on public.executive_action_events;
create policy executive_action_events_actor_insert on public.executive_action_events
for insert to authenticated
with check (
  actor_user_id=auth.uid()
  and public.is_business_member(business_id)
  and exists (
    select 1 from public.executive_actions a
    where a.id=executive_action_events.action_id
      and a.business_id=executive_action_events.business_id
      and (
        public.has_business_role(a.business_id,array['owner','admin','manager']::public.business_role[])
        or a.assignee_user_id=auth.uid()
      )
  )
);

-- Managers can assign tasks to active members of this business/branch.
create or replace function public.list_executive_action_assignees(
  p_business_id uuid,
  p_branch_id uuid default null
)
returns table(user_id uuid,full_name text,role public.business_role)
language plpgsql
stable
security definer
set search_path = ''
as $$
begin
  if not public.has_business_role(p_business_id,array['owner','admin','manager']::public.business_role[]) then
    raise exception 'Only an owner, administrator or manager can list action assignees';
  end if;
  if p_branch_id is not null and not exists (
    select 1 from public.branches b where b.id=p_branch_id and b.business_id=p_business_id and b.is_active
  ) then
    raise exception 'Selected branch does not belong to this business';
  end if;
  return query
    select m.user_id,coalesce(nullif(trim(p.full_name),''),'Business employee'),m.role
    from public.business_members m
    left join public.profiles p on p.id=m.user_id
    where m.business_id=p_business_id and m.is_active
      and (
        p_branch_id is null
        or m.role in ('owner','admin','manager')
        or exists (
          select 1 from public.branch_members bm
          where bm.business_id=p_business_id
            and bm.branch_id=p_branch_id
            and bm.user_id=m.user_id
            and bm.is_active
        )
      )
    order by case m.role when 'owner' then 0 when 'admin' then 1 when 'manager' then 2 else 3 end,
             coalesce(nullif(trim(p.full_name),''),'Business employee');
end;
$$;

revoke all on function public.list_executive_action_assignees(uuid,uuid) from public;
grant execute on function public.list_executive_action_assignees(uuid,uuid) to authenticated;

-- Enable Supabase Realtime for live updates where the standard publication is available.
do $$
begin
  if exists (select 1 from pg_publication where pubname='supabase_realtime') then
    if not exists (
      select 1 from pg_publication_tables
      where pubname='supabase_realtime' and schemaname='public' and tablename='executive_actions'
    ) then
      alter publication supabase_realtime add table public.executive_actions;
    end if;
    if not exists (
      select 1 from pg_publication_tables
      where pubname='supabase_realtime' and schemaname='public' and tablename='executive_action_events'
    ) then
      alter publication supabase_realtime add table public.executive_action_events;
    end if;
  end if;
end $$;

commit;
