-- White Lion SME OS: phone unlocking and device services module.
-- Run this migration once in Supabase SQL Editor after merging the matching application PR.
begin;

alter table public.business_industry_modules
  drop constraint if exists business_industry_modules_module_key_check;

insert into public.business_industry_modules (business_id,module_key,is_enabled)
select id,'phone_unlocking',false
from public.businesses
on conflict (business_id,module_key) do nothing;

-- The original module-seeding trigger predates this module. Seed it for future businesses too.
create or replace function public.seed_phone_unlocking_module()
returns trigger
language plpgsql
security definer
set search_path = public
as $
begin
  insert into public.business_industry_modules(business_id,module_key,is_enabled)
  values(new.id,'phone_unlocking',false)
  on conflict (business_id,module_key) do nothing;
  return new;
end;
$;

drop trigger if exists phone_unlocking_module_seed on public.businesses;
create trigger phone_unlocking_module_seed
after insert on public.businesses
for each row execute function public.seed_phone_unlocking_module();

create table if not exists public.phone_unlocking_services (
  id uuid primary key default gen_random_uuid(),
  business_id uuid not null references public.businesses(id) on delete cascade,
  service_name text not null check (length(trim(service_name)) between 2 and 120),
  description text,
  default_price numeric(18,2) not null default 0 check (default_price >= 0),
  is_active boolean not null default true,
  created_by uuid not null default auth.uid() references auth.users(id),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (id,business_id),
  unique (business_id,service_name)
);

create table if not exists public.phone_unlocking_orders (
  id uuid primary key default gen_random_uuid(),
  business_id uuid not null references public.businesses(id) on delete cascade,
  branch_id uuid not null,
  customer_id uuid,
  reference text not null,
  customer_name text not null check (length(trim(customer_name)) >= 2),
  customer_phone text,
  device_brand text not null,
  device_model text not null,
  imei text not null check (imei ~ '^[0-9]{14,16}$'),
  network_name text not null,
  country text,
  service_name text not null,
  provider_name text,
  provider_reference text,
  provider_cost numeric(18,2) not null default 0 check (provider_cost >= 0),
  service_price numeric(18,2) not null check (service_price >= 0),
  amount_paid numeric(18,2) not null default 0 check (amount_paid >= 0 and amount_paid <= service_price),
  status text not null default 'received'
    check (status in ('received','quoted','awaiting_payment','processing','completed','failed','cancelled','refunded')),
  notes text,
  created_by uuid not null default auth.uid() references auth.users(id),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  completed_at timestamptz,
  unique (business_id,reference),
  unique (id,business_id),
  foreign key (branch_id,business_id) references public.branches(id,business_id),
  foreign key (customer_id,business_id) references public.customers(id,business_id)
);

create table if not exists public.phone_unlocking_payments (
  id uuid primary key default gen_random_uuid(),
  business_id uuid not null references public.businesses(id) on delete cascade,
  order_id uuid not null,
  amount numeric(18,2) not null check (amount > 0),
  payment_method text not null check (payment_method in ('cash','mobile_money','bank_transfer','card','other')),
  payment_reference text,
  notes text,
  received_by uuid not null default auth.uid() references auth.users(id),
  created_at timestamptz not null default now(),
  foreign key (order_id,business_id)
    references public.phone_unlocking_orders(id,business_id) on delete cascade
);

create index if not exists phone_unlocking_orders_business_created_idx
  on public.phone_unlocking_orders(business_id,created_at desc);
create index if not exists phone_unlocking_orders_business_status_idx
  on public.phone_unlocking_orders(business_id,status,created_at desc);
create index if not exists phone_unlocking_payments_order_idx
  on public.phone_unlocking_payments(business_id,order_id,created_at desc);
create index if not exists phone_unlocking_services_business_idx
  on public.phone_unlocking_services(business_id,is_active,service_name);

alter table public.phone_unlocking_services enable row level security;
alter table public.phone_unlocking_orders enable row level security;
alter table public.phone_unlocking_payments enable row level security;

drop policy if exists phone_unlocking_services_read on public.phone_unlocking_services;
create policy phone_unlocking_services_read on public.phone_unlocking_services
for select to authenticated
using (public.is_business_member(business_id));

drop policy if exists phone_unlocking_services_manage on public.phone_unlocking_services;
create policy phone_unlocking_services_manage on public.phone_unlocking_services
for all to authenticated
using (public.has_business_role(business_id,array['owner','admin','manager']::public.business_role[]))
with check (public.has_business_role(business_id,array['owner','admin','manager']::public.business_role[]));

drop policy if exists phone_unlocking_orders_read on public.phone_unlocking_orders;
create policy phone_unlocking_orders_read on public.phone_unlocking_orders
for select to authenticated
using (public.has_business_role(business_id,array['owner','admin','manager']::public.business_role[]));

drop policy if exists phone_unlocking_orders_insert on public.phone_unlocking_orders;
create policy phone_unlocking_orders_insert on public.phone_unlocking_orders
for insert to authenticated
with check (
  created_by = auth.uid()
  and public.has_business_role(business_id,array['owner','admin','manager']::public.business_role[])
);

drop policy if exists phone_unlocking_orders_update on public.phone_unlocking_orders;
create policy phone_unlocking_orders_update on public.phone_unlocking_orders
for update to authenticated
using (public.has_business_role(business_id,array['owner','admin','manager']::public.business_role[]))
with check (public.has_business_role(business_id,array['owner','admin','manager']::public.business_role[]));

drop policy if exists phone_unlocking_payments_read on public.phone_unlocking_payments;
create policy phone_unlocking_payments_read on public.phone_unlocking_payments
for select to authenticated
using (public.has_business_role(business_id,array['owner','admin','manager']::public.business_role[]));

revoke all on public.phone_unlocking_services from anon;
revoke all on public.phone_unlocking_orders from anon;
revoke all on public.phone_unlocking_payments from anon;
grant select on public.phone_unlocking_services to authenticated;
grant insert (business_id,service_name,description,default_price) on public.phone_unlocking_services to authenticated;
grant update (service_name,description,default_price,is_active,updated_at) on public.phone_unlocking_services to authenticated;

grant select on public.phone_unlocking_orders to authenticated;
grant insert (
  business_id,branch_id,reference,customer_name,customer_phone,device_brand,device_model,
  imei,network_name,country,service_name,provider_name,provider_reference,provider_cost,
  service_price,notes
) on public.phone_unlocking_orders to authenticated;
grant update (status,updated_at,completed_at,notes,provider_name,provider_reference,provider_cost,service_price)
  on public.phone_unlocking_orders to authenticated;
grant select on public.phone_unlocking_payments to authenticated;

create or replace function public.record_phone_unlocking_payment(
  p_business_id uuid,
  p_order_id uuid,
  p_amount numeric,
  p_payment_method text,
  p_payment_reference text default null,
  p_notes text default null
) returns uuid
language plpgsql
security definer
set search_path = public, auth
as $$
declare
  v_order public.phone_unlocking_orders%rowtype;
  v_payment_id uuid := gen_random_uuid();
begin
  if auth.uid() is null then raise exception 'Authentication required'; end if;
  if not public.has_business_role(p_business_id,array['owner','admin','manager']::public.business_role[]) then
    raise exception 'Not authorised to record unlocking payments';
  end if;
  if p_amount is null or p_amount <= 0 then raise exception 'Payment amount must be greater than zero'; end if;
  if p_payment_method not in ('cash','mobile_money','bank_transfer','card','other') then
    raise exception 'Unsupported payment method';
  end if;

  select * into v_order
  from public.phone_unlocking_orders
  where id=p_order_id and business_id=p_business_id
  for update;
  if not found then raise exception 'Unlocking order not found'; end if;
  if v_order.status in ('cancelled','refunded','failed') then
    raise exception 'Payments cannot be recorded against a cancelled, refunded or failed order';
  end if;
  if v_order.amount_paid + p_amount > v_order.service_price then
    raise exception 'Payment exceeds the outstanding order balance';
  end if;

  insert into public.phone_unlocking_payments(
    id,business_id,order_id,amount,payment_method,payment_reference,notes,received_by
  ) values (
    v_payment_id,p_business_id,p_order_id,p_amount,p_payment_method,
    nullif(trim(coalesce(p_payment_reference,'')),''),
    nullif(trim(coalesce(p_notes,'')),''),
    auth.uid()
  );

  update public.phone_unlocking_orders
  set amount_paid=amount_paid+p_amount,updated_at=now()
  where id=p_order_id and business_id=p_business_id;

  insert into public.audit_logs(business_id,actor_user_id,action,entity_table,entity_id,details)
  values(p_business_id,auth.uid(),'phone_unlocking_payment_recorded','phone_unlocking_payments',
    v_payment_id::text,jsonb_build_object('order_id',p_order_id,'amount',p_amount,'method',p_payment_method));

  return v_payment_id;
end;
$$;

revoke all on function public.record_phone_unlocking_payment(uuid,uuid,numeric,text,text,text) from public;
grant execute on function public.record_phone_unlocking_payment(uuid,uuid,numeric,text,text,text) to authenticated;

commit;
