-- White Lion Phone Unlocking: consolidated database installer
-- Run once in the Supabase SQL Editor after the core White Lion SME OS database migrations.
-- This combines migrations 033, 034 and 035 in dependency order.
-- It creates the business-scoped service catalogue, orders, payment/refund records,
-- provider catalogue, owner approval gate, and protected provider-submission RPCs.
-- It does NOT configure or expose the Mobile-Unlock API key; configure that as a Supabase Edge Function secret.

-- ============================================================
-- SOURCE: supabase/migrations/033_phone_unlocking_services.sql
-- ============================================================
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
as $seed$
begin
  insert into public.business_industry_modules(business_id,module_key,is_enabled)
  values(new.id,'phone_unlocking',false)
  on conflict (business_id,module_key) do nothing;
  return new;
end;
$seed$;

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
  amount_refunded numeric(18,2) not null default 0 check (amount_refunded >= 0 and amount_refunded <= amount_paid),
  status text not null default 'received'
    check (status in ('received','quoted','awaiting_payment','processing','completed','failed','cancelled','refunded')),
  check (status <> 'cancelled' or amount_paid = amount_refunded),
  check (status <> 'refunded' or (amount_paid > 0 and amount_refunded = amount_paid)),
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
create table if not exists public.phone_unlocking_refunds (
  id uuid primary key default gen_random_uuid(),
  business_id uuid not null references public.businesses(id) on delete cascade,
  order_id uuid not null,
  amount numeric(18,2) not null check (amount > 0),
  refund_method text not null check (refund_method in ('cash','mobile_money','bank_transfer','card','other')),
  refund_reference text,
  notes text,
  issued_by uuid not null default auth.uid() references auth.users(id),
  created_at timestamptz not null default now(),
  foreign key (order_id,business_id)
    references public.phone_unlocking_orders(id,business_id) on delete cascade
);

create index if not exists phone_unlocking_refunds_order_idx
  on public.phone_unlocking_refunds(business_id,order_id,created_at desc);

create index if not exists phone_unlocking_payments_order_idx
  on public.phone_unlocking_payments(business_id,order_id,created_at desc);
create index if not exists phone_unlocking_services_business_idx
  on public.phone_unlocking_services(business_id,is_active,service_name);

alter table public.phone_unlocking_services enable row level security;
alter table public.phone_unlocking_orders enable row level security;
alter table public.phone_unlocking_payments enable row level security;
alter table public.phone_unlocking_refunds enable row level security;

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

drop policy if exists phone_unlocking_refunds_read on public.phone_unlocking_refunds;
create policy phone_unlocking_refunds_read on public.phone_unlocking_refunds
for select to authenticated
using (public.has_business_role(business_id,array['owner','admin','manager']::public.business_role[]));

drop policy if exists phone_unlocking_payments_read on public.phone_unlocking_payments;
create policy phone_unlocking_payments_read on public.phone_unlocking_payments
for select to authenticated
using (public.has_business_role(business_id,array['owner','admin','manager']::public.business_role[]));

revoke all on public.phone_unlocking_services from anon;
revoke all on public.phone_unlocking_orders from anon;
revoke all on public.phone_unlocking_payments from anon;
revoke all on public.phone_unlocking_refunds from anon;
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
grant select on public.phone_unlocking_refunds to authenticated;

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

create or replace function public.record_phone_unlocking_refund(
  p_business_id uuid,
  p_order_id uuid,
  p_amount numeric,
  p_refund_method text,
  p_refund_reference text default null,
  p_notes text default null
) returns uuid
language plpgsql
security definer
set search_path = public, auth
as $refund$
declare
  v_order public.phone_unlocking_orders%rowtype;
  v_refund_id uuid := gen_random_uuid();
  v_new_refunded numeric(18,2);
begin
  if auth.uid() is null then raise exception 'Authentication required'; end if;
  if not public.has_business_role(p_business_id,array['owner','admin','manager']::public.business_role[]) then
    raise exception 'Not authorised to issue unlocking refunds';
  end if;
  if p_amount is null or p_amount <= 0 then raise exception 'Refund amount must be greater than zero'; end if;
  if p_refund_method not in ('cash','mobile_money','bank_transfer','card','other') then
    raise exception 'Unsupported refund method';
  end if;

  select * into v_order
  from public.phone_unlocking_orders
  where id=p_order_id and business_id=p_business_id
  for update;
  if not found then raise exception 'Unlocking order not found'; end if;
  if v_order.status='cancelled' then raise exception 'Cancelled orders cannot be refunded through this workflow'; end if;

  v_new_refunded := v_order.amount_refunded + p_amount;
  if v_new_refunded > v_order.amount_paid then
    raise exception 'Refund exceeds the amount received from the customer';
  end if;

  insert into public.phone_unlocking_refunds(
    id,business_id,order_id,amount,refund_method,refund_reference,notes,issued_by
  ) values (
    v_refund_id,p_business_id,p_order_id,p_amount,p_refund_method,
    nullif(trim(coalesce(p_refund_reference,'')),''),
    nullif(trim(coalesce(p_notes,'')),''),
    auth.uid()
  );

  update public.phone_unlocking_orders
  set amount_refunded=v_new_refunded,
      status=case when v_new_refunded=v_order.amount_paid then 'refunded' else status end,
      updated_at=now()
  where id=p_order_id and business_id=p_business_id;

  insert into public.audit_logs(business_id,actor_user_id,action,entity_table,entity_id,details)
  values(p_business_id,auth.uid(),'phone_unlocking_refund_recorded','phone_unlocking_refunds',
    v_refund_id::text,jsonb_build_object('order_id',p_order_id,'amount',p_amount,'method',p_refund_method));

  return v_refund_id;
end;
$refund$;

revoke all on function public.record_phone_unlocking_refund(uuid,uuid,numeric,text,text,text) from public;
grant execute on function public.record_phone_unlocking_refund(uuid,uuid,numeric,text,text,text) to authenticated;

commit;


-- ============================================================
-- SOURCE: supabase/migrations/034_mobile_unlock_provider_catalogue.sql
-- ============================================================
begin;
create table if not exists public.phone_unlocking_provider_services (
 id uuid primary key default gen_random_uuid(),
 business_id uuid not null references public.businesses(id) on delete cascade,
 provider_service_id text not null,
 provider_service_type text not null default 'IMEI',
 provider_group text,
 service_name text not null,
 provider_credit numeric(18,4),
 provider_currency text,
 delivery_time text,
 description text,
 quantity integer,
 requires_custom jsonb not null default '[]'::jsonb,
 is_active boolean not null default true,
 last_synced_at timestamptz not null default now(),
 created_at timestamptz not null default now(),
 updated_at timestamptz not null default now(),
 unique (business_id,provider_service_type,provider_service_id)
);
alter table public.phone_unlocking_services
 add column if not exists provider_service_id text,
 add column if not exists provider_service_type text,
 add column if not exists provider_group text,
 add column if not exists provider_cost numeric(18,4),
 add column if not exists provider_currency text,
 add column if not exists provider_delivery_time text,
 add column if not exists provider_info text,
 add column if not exists provider_requires_custom jsonb;
create unique index if not exists phone_unlocking_services_provider_unique
 on public.phone_unlocking_services(business_id,provider_service_type,provider_service_id)
 where provider_service_id is not null;
create index if not exists phone_unlocking_provider_services_business_idx
 on public.phone_unlocking_provider_services(business_id,is_active,provider_group,service_name);
alter table public.phone_unlocking_provider_services enable row level security;
drop policy if exists phone_unlocking_provider_services_read on public.phone_unlocking_provider_services;
create policy phone_unlocking_provider_services_read on public.phone_unlocking_provider_services
 for select to authenticated using (public.has_business_role(business_id,array['owner','admin','manager']::public.business_role[]));
drop policy if exists phone_unlocking_provider_services_manage on public.phone_unlocking_provider_services;
create policy phone_unlocking_provider_services_manage on public.phone_unlocking_provider_services
 for all to authenticated using (public.has_business_role(business_id,array['owner','admin','manager']::public.business_role[]))
 with check (public.has_business_role(business_id,array['owner','admin','manager']::public.business_role[]));
revoke all on public.phone_unlocking_provider_services from anon;
grant select,insert,update on public.phone_unlocking_provider_services to authenticated;
commit;

-- ============================================================
-- SOURCE: supabase/migrations/035_phone_unlocking_owner_approval.sql
-- ============================================================
-- Owner-controlled approval and safe Mobile-Unlock submission gate.
begin;

alter table public.phone_unlocking_orders
  add column if not exists provider_service_id text,
  add column if not exists provider_service_type text,
  add column if not exists approval_status text not null default 'pending'
    check (approval_status in ('pending','approved','rejected')),
  add column if not exists approved_by uuid references auth.users(id),
  add column if not exists approved_at timestamptz,
  add column if not exists rejected_by uuid references auth.users(id),
  add column if not exists rejected_at timestamptz,
  add column if not exists rejection_reason text,
  add column if not exists provider_submission_status text not null default 'not_submitted'
    check (provider_submission_status in ('not_submitted','submitting','submitted','failed','unknown')),
  add column if not exists provider_submission_attempted_at timestamptz,
  add column if not exists provider_submission_message text;

create index if not exists phone_unlocking_orders_approval_idx
  on public.phone_unlocking_orders(business_id,approval_status,created_at desc);

grant insert (provider_service_id,provider_service_type) on public.phone_unlocking_orders to authenticated;
grant select on public.phone_unlocking_orders to authenticated;

create or replace function public.approve_phone_unlocking_order(
  p_business_id uuid,
  p_order_id uuid
) returns void
language plpgsql
security definer
set search_path = public, auth
as $approve$
declare
  v_order public.phone_unlocking_orders%rowtype;
begin
  if auth.uid() is null then raise exception 'Authentication required'; end if;
  if not public.has_business_role(p_business_id,array['owner']::public.business_role[]) then
    raise exception 'Only the business owner can approve phone unlocking orders';
  end if;
  select * into v_order from public.phone_unlocking_orders
   where id=p_order_id and business_id=p_business_id for update;
  if not found then raise exception 'Unlocking order not found'; end if;
  if v_order.approval_status <> 'pending' then raise exception 'This order has already been reviewed'; end if;
  if v_order.status not in ('received','quoted','awaiting_payment') then
    raise exception 'This order is not eligible for approval';
  end if;
  if v_order.amount_paid < v_order.service_price then
    raise exception 'Full customer payment is required before approval';
  end if;
  update public.phone_unlocking_orders
     set approval_status='approved',approved_by=auth.uid(),approved_at=now(),
         rejected_by=null,rejected_at=null,rejection_reason=null,updated_at=now()
   where id=p_order_id and business_id=p_business_id;
  insert into public.audit_logs(business_id,actor_user_id,action,entity_table,entity_id,details)
  values(p_business_id,auth.uid(),'phone_unlocking_order_approved','phone_unlocking_orders',
    p_order_id::text,jsonb_build_object('reference',v_order.reference,'provider_submission','requires_explicit_server_action'));
end;
$approve$;

create or replace function public.reject_phone_unlocking_order(
  p_business_id uuid,
  p_order_id uuid,
  p_reason text default null
) returns void
language plpgsql
security definer
set search_path = public, auth
as $reject$
declare
  v_order public.phone_unlocking_orders%rowtype;
begin
  if auth.uid() is null then raise exception 'Authentication required'; end if;
  if not public.has_business_role(p_business_id,array['owner']::public.business_role[]) then
    raise exception 'Only the business owner can reject phone unlocking orders';
  end if;
  select * into v_order from public.phone_unlocking_orders
   where id=p_order_id and business_id=p_business_id for update;
  if not found then raise exception 'Unlocking order not found'; end if;
  if v_order.approval_status <> 'pending' then raise exception 'This order has already been reviewed'; end if;
  if v_order.provider_submission_status <> 'not_submitted' then
    raise exception 'An order with a provider submission attempt cannot be rejected here';
  end if;
  update public.phone_unlocking_orders
     set approval_status='rejected',rejected_by=auth.uid(),rejected_at=now(),
         rejection_reason=nullif(left(trim(coalesce(p_reason,'')),500),''),
         status=case when amount_paid=0 then 'cancelled' else status end,updated_at=now()
   where id=p_order_id and business_id=p_business_id;
  insert into public.audit_logs(business_id,actor_user_id,action,entity_table,entity_id,details)
  values(p_business_id,auth.uid(),'phone_unlocking_order_rejected','phone_unlocking_orders',
    p_order_id::text,jsonb_build_object('reference',v_order.reference,'reason',left(coalesce(p_reason,''),500)));
end;
$reject$;

-- Atomically claim a provider submission. A second click/retry cannot submit the same order twice.
create or replace function public.claim_phone_unlocking_provider_submission(
  p_business_id uuid,
  p_order_id uuid
) returns jsonb
language plpgsql
security definer
set search_path = public, auth
as $claim$
declare
  v_order public.phone_unlocking_orders%rowtype;
begin
  if auth.uid() is null then raise exception 'Authentication required'; end if;
  if not public.has_business_role(p_business_id,array['owner']::public.business_role[]) then
    raise exception 'Only the business owner can submit approved provider orders';
  end if;
  select * into v_order from public.phone_unlocking_orders
   where id=p_order_id and business_id=p_business_id for update;
  if not found then raise exception 'Unlocking order not found'; end if;
  if v_order.approval_status <> 'approved' or v_order.approved_by <> auth.uid() then
    raise exception 'This order has not been approved by the signed-in business owner';
  end if;
  if v_order.amount_paid < v_order.service_price then raise exception 'Full customer payment is required'; end if;
  if v_order.provider_service_id is null or v_order.provider_service_type <> 'IMEI' then
    raise exception 'This order has no supported Mobile-Unlock IMEI service mapping';
  end if;
  if v_order.provider_submission_status <> 'not_submitted' then
    raise exception 'A provider submission has already been attempted. Reconcile its status before any retry';
  end if;
  if v_order.status in ('cancelled','failed','refunded','completed') then
    raise exception 'This order is not in a submit-ready state';
  end if;
  update public.phone_unlocking_orders
     set provider_submission_status='submitting',
         provider_submission_attempted_at=now(),
         provider_submission_message='Owner-approved submission started',
         updated_at=now()
   where id=p_order_id and business_id=p_business_id
   returning * into v_order;
  return to_jsonb(v_order);
end;
$claim$;

create or replace function public.finish_phone_unlocking_provider_submission(
  p_business_id uuid,
  p_order_id uuid,
  p_outcome text,
  p_provider_reference text default null,
  p_message text default null
) returns void
language plpgsql
security definer
set search_path = public, auth
as $finish$
declare
  v_order public.phone_unlocking_orders%rowtype;
begin
  if auth.uid() is null then raise exception 'Authentication required'; end if;
  if not public.has_business_role(p_business_id,array['owner']::public.business_role[]) then
    raise exception 'Only the business owner can finalise provider submission';
  end if;
  if p_outcome not in ('submitted','failed','unknown') then raise exception 'Invalid provider submission outcome'; end if;
  select * into v_order from public.phone_unlocking_orders
   where id=p_order_id and business_id=p_business_id for update;
  if not found then raise exception 'Unlocking order not found'; end if;
  if v_order.provider_submission_status <> 'submitting' then
    raise exception 'Order is not currently marked as submitting';
  end if;
  update public.phone_unlocking_orders
     set provider_submission_status=p_outcome,
         provider_reference=case when p_outcome='submitted' then nullif(trim(coalesce(p_provider_reference,'')),'') else provider_reference end,
         provider_submission_message=left(coalesce(p_message,''),500),
         status=case when p_outcome='submitted' then 'processing' else status end,
         provider_name=case when p_outcome='submitted' then 'Mobile-Unlock' else provider_name end,
         updated_at=now()
   where id=p_order_id and business_id=p_business_id;
  insert into public.audit_logs(business_id,actor_user_id,action,entity_table,entity_id,details)
  values(p_business_id,auth.uid(),'phone_unlocking_provider_submission_'||p_outcome,
    'phone_unlocking_orders',p_order_id::text,
    jsonb_build_object('reference',v_order.reference,'provider_reference',p_provider_reference,'message',left(coalesce(p_message,''),500)));
end;
$finish$;

revoke all on function public.approve_phone_unlocking_order(uuid,uuid) from public;
revoke all on function public.reject_phone_unlocking_order(uuid,uuid,text) from public;
revoke all on function public.claim_phone_unlocking_provider_submission(uuid,uuid) from public;
revoke all on function public.finish_phone_unlocking_provider_submission(uuid,uuid,text,text,text) from public;
grant execute on function public.approve_phone_unlocking_order(uuid,uuid) to authenticated;
grant execute on function public.reject_phone_unlocking_order(uuid,uuid,text) to authenticated;
grant execute on function public.claim_phone_unlocking_provider_submission(uuid,uuid) to authenticated;
grant execute on function public.finish_phone_unlocking_provider_submission(uuid,uuid,text,text,text) to authenticated;

commit;

