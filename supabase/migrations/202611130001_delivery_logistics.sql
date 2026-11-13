-- White Lion SME OS: delivery and logistics module
-- Run once in Supabase SQL Editor. Does not modify legacy online_orders tables.
create extension if not exists pgcrypto;

create table if not exists public.delivery_riders (
  id uuid primary key default gen_random_uuid(),
  business_id uuid not null references public.businesses(id) on delete cascade,
  full_name text not null,
  phone text not null,
  vehicle_type text,
  vehicle_registration text,
  is_active boolean not null default true,
  created_at timestamptz not null default now(),
  unique (business_id, phone)
);

create table if not exists public.delivery_jobs (
  id uuid primary key default gen_random_uuid(),
  business_id uuid not null references public.businesses(id) on delete cascade,
  order_id uuid not null references public.online_store_orders(id) on delete restrict,
  rider_id uuid references public.delivery_riders(id) on delete set null,
  tracking_code text not null unique default upper(substr(encode(gen_random_bytes(8),'hex'),1,10)),
  delivery_pin text not null default lpad((floor(random()*1000000))::int::text,6,'0'),
  delivery_address text not null,
  delivery_fee numeric(14,2) not null default 0 check (delivery_fee >= 0),
  delivery_status text not null default 'awaiting_collection'
    check (delivery_status in ('awaiting_collection','collected','in_transit','delivered','failed','returned','cancelled')),
  cash_on_delivery numeric(14,2) not null default 0 check (cash_on_delivery >= 0),
  cash_collected numeric(14,2) not null default 0 check (cash_collected >= 0),
  delivery_notes text,
  assigned_at timestamptz,
  collected_at timestamptz,
  delivered_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique(order_id)
);

create table if not exists public.delivery_events (
  id uuid primary key default gen_random_uuid(),
  business_id uuid not null references public.businesses(id) on delete cascade,
  delivery_job_id uuid not null references public.delivery_jobs(id) on delete cascade,
  event_status text not null,
  event_note text,
  created_at timestamptz not null default now()
);

create index if not exists delivery_jobs_business_created_idx on public.delivery_jobs(business_id,created_at desc);
create index if not exists delivery_jobs_tracking_idx on public.delivery_jobs(tracking_code);
create index if not exists delivery_events_job_idx on public.delivery_events(delivery_job_id,created_at);

alter table public.delivery_riders enable row level security;
alter table public.delivery_jobs enable row level security;
alter table public.delivery_events enable row level security;

drop policy if exists delivery_riders_member_read on public.delivery_riders;
create policy delivery_riders_member_read on public.delivery_riders for select to authenticated
using (exists(select 1 from public.business_members bm where bm.business_id=delivery_riders.business_id and bm.user_id=auth.uid()));
drop policy if exists delivery_riders_manager_insert on public.delivery_riders;
create policy delivery_riders_manager_insert on public.delivery_riders for insert to authenticated
with check (exists(select 1 from public.business_members bm where bm.business_id=delivery_riders.business_id and bm.user_id=auth.uid() and lower(bm.role::text) in ('owner','admin','manager')));
drop policy if exists delivery_riders_manager_update on public.delivery_riders;
create policy delivery_riders_manager_update on public.delivery_riders for update to authenticated
using (exists(select 1 from public.business_members bm where bm.business_id=delivery_riders.business_id and bm.user_id=auth.uid() and lower(bm.role::text) in ('owner','admin','manager')))
with check (exists(select 1 from public.business_members bm where bm.business_id=delivery_riders.business_id and bm.user_id=auth.uid() and lower(bm.role::text) in ('owner','admin','manager')));
drop policy if exists delivery_jobs_member_read on public.delivery_jobs;
create policy delivery_jobs_member_read on public.delivery_jobs for select to authenticated
using (exists(select 1 from public.business_members bm where bm.business_id=delivery_jobs.business_id and bm.user_id=auth.uid()));
drop policy if exists delivery_events_member_read on public.delivery_events;
create policy delivery_events_member_read on public.delivery_events for select to authenticated
using (exists(select 1 from public.business_members bm where bm.business_id=delivery_events.business_id and bm.user_id=auth.uid()));

create or replace function public.create_delivery_job(
  p_order_id uuid, p_delivery_fee numeric default 0, p_delivery_address text default null,
  p_cash_on_delivery numeric default 0, p_notes text default null
) returns jsonb language plpgsql security definer set search_path=public,pg_temp as $$
declare o public.online_store_orders%rowtype; j public.delivery_jobs%rowtype; v_uid uuid:=auth.uid();
begin
  select * into o from public.online_store_orders where id=p_order_id for update;
  if not found then raise exception 'Online order not found'; end if;
  if not exists(select 1 from public.business_members bm where bm.business_id=o.business_id and bm.user_id=v_uid and lower(bm.role::text) in ('owner','admin','manager')) then
    raise exception 'You do not have permission to create deliveries for this business';
  end if;
  if coalesce(nullif(trim(p_delivery_address),''),nullif(trim(o.delivery_address),'')) is null then raise exception 'A delivery address is required'; end if;
  insert into public.delivery_jobs(business_id,order_id,delivery_address,delivery_fee,cash_on_delivery,delivery_notes)
  values(o.business_id,o.id,coalesce(nullif(trim(p_delivery_address),''),o.delivery_address),greatest(coalesce(p_delivery_fee,0),0),greatest(coalesce(p_cash_on_delivery,0),0),p_notes)
  on conflict(order_id) do update set delivery_address=excluded.delivery_address,delivery_fee=excluded.delivery_fee,cash_on_delivery=excluded.cash_on_delivery,delivery_notes=excluded.delivery_notes,updated_at=now()
  returning * into j;
  update public.online_store_orders
    set delivery_fee=j.delivery_fee,
        delivery_address=j.delivery_address,
        total_amount=greatest(coalesce(subtotal,0)+j.delivery_fee-coalesce(discount,0),0),
        updated_at=now()
    where id=o.id;
  insert into public.delivery_events(business_id,delivery_job_id,event_status,event_note)
  values(j.business_id,j.id,'awaiting_collection','Delivery job created');
  return jsonb_build_object('status','success','delivery_id',j.id,'tracking_code',j.tracking_code,'delivery_pin',j.delivery_pin);
end $$;

create or replace function public.assign_delivery_rider(p_delivery_id uuid,p_rider_id uuid)
returns jsonb language plpgsql security definer set search_path=public,pg_temp as $$
declare j public.delivery_jobs%rowtype; r public.delivery_riders%rowtype; v_uid uuid:=auth.uid();
begin
 select * into j from public.delivery_jobs where id=p_delivery_id for update;
 if not found then raise exception 'Delivery job not found'; end if;
 if not exists(select 1 from public.business_members bm where bm.business_id=j.business_id and bm.user_id=v_uid and lower(bm.role::text) in ('owner','admin','manager')) then raise exception 'Permission denied'; end if;
 select * into r from public.delivery_riders where id=p_rider_id and business_id=j.business_id and is_active;
 if not found then raise exception 'Active rider not found for this business'; end if;
 update public.delivery_jobs set rider_id=r.id,assigned_at=now(),updated_at=now() where id=j.id;
 insert into public.delivery_events(business_id,delivery_job_id,event_status,event_note) values(j.business_id,j.id,'awaiting_collection','Assigned to '||r.full_name);
 return jsonb_build_object('status','success');
end $$;

create or replace function public.update_delivery_status(
 p_delivery_id uuid,p_new_status text,p_event_note text default null,p_cash_collected numeric default null,p_delivery_pin text default null
) returns jsonb language plpgsql security definer set search_path=public,pg_temp as $$
declare j public.delivery_jobs%rowtype; v_uid uuid:=auth.uid(); v_status text:=lower(trim(p_new_status));
begin
 select * into j from public.delivery_jobs where id=p_delivery_id for update;
 if not found then raise exception 'Delivery job not found'; end if;
 if not exists(select 1 from public.business_members bm where bm.business_id=j.business_id and bm.user_id=v_uid and lower(bm.role::text) in ('owner','admin','manager','cashier')) then raise exception 'Permission denied'; end if;
 if v_status not in ('awaiting_collection','collected','in_transit','delivered','failed','returned','cancelled') then raise exception 'Invalid delivery status'; end if;
 if v_status='delivered' and (p_delivery_pin is null or p_delivery_pin<>j.delivery_pin) then raise exception 'A valid customer delivery PIN is required'; end if;
 update public.delivery_jobs set delivery_status=v_status,updated_at=now(),
 collected_at=case when v_status='collected' then coalesce(collected_at,now()) else collected_at end,
 delivered_at=case when v_status='delivered' then now() else delivered_at end,
 cash_collected=case when p_cash_collected is null then cash_collected else greatest(p_cash_collected,0) end
 where id=j.id;
 insert into public.delivery_events(business_id,delivery_job_id,event_status,event_note)
 values(j.business_id,j.id,v_status,p_event_note);
 return jsonb_build_object('status','success');
end $$;

create or replace function public.get_public_delivery_tracking(p_tracking_code text)
returns jsonb language plpgsql stable security definer set search_path=public,pg_temp as $$
declare j public.delivery_jobs%rowtype; o public.online_store_orders%rowtype; r public.delivery_riders%rowtype; ev jsonb;
begin
 select * into j from public.delivery_jobs where tracking_code=upper(trim(p_tracking_code));
 if not found then return jsonb_build_object('status','not_found'); end if;
 select * into o from public.online_store_orders where id=j.order_id;
 if j.rider_id is not null then select * into r from public.delivery_riders where id=j.rider_id; end if;
 select coalesce(jsonb_agg(jsonb_build_object('status',event_status,'note',event_note,'at',created_at) order by created_at), '[]'::jsonb)
 into ev from public.delivery_events where delivery_job_id=j.id;
 return jsonb_build_object('status','success','tracking',jsonb_build_object(
  'tracking_code',j.tracking_code,'order_number',o.order_number,'delivery_status',j.delivery_status,
  'delivery_address',j.delivery_address,'delivery_fee',j.delivery_fee,'rider_name',r.full_name,
  'rider_phone',r.phone,'created_at',j.created_at,'updated_at',j.updated_at,'delivered_at',j.delivered_at,'events',ev));
end $$;

grant execute on function public.create_delivery_job(uuid,numeric,text,numeric,text) to authenticated;
grant execute on function public.assign_delivery_rider(uuid,uuid) to authenticated;
grant execute on function public.update_delivery_status(uuid,text,text,numeric,text) to authenticated;
grant execute on function public.get_public_delivery_tracking(text) to anon,authenticated;
