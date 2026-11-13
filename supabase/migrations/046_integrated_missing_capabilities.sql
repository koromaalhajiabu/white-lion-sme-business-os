-- White Lion SME Business OS — Migration 046
-- Integrated missing capabilities: staff/payroll, customer loyalty, online orders,
-- supplier collaboration, marketplace listings and franchise controls.
-- Additive migration. Existing sales, customers, suppliers, branches and ledger remain intact.

begin;

-- 1) Employee records and payroll. Payroll runs are prepared/approved separately;
--    net pay is calculated from gross less deductions and cannot be negative.
create table if not exists public.employees (
  id uuid primary key default gen_random_uuid(),
  business_id uuid not null references public.businesses(id) on delete cascade,
  employee_code text not null,
  full_name text not null check (length(trim(full_name)) between 2 and 160),
  job_title text,
  phone text,
  email text,
  branch_id uuid,
  employment_status text not null default 'active'
    check (employment_status in ('active','on_leave','suspended','terminated')),
  start_date date,
  base_salary numeric(18,2) not null default 0 check (base_salary >= 0),
  pay_frequency text not null default 'monthly'
    check (pay_frequency in ('weekly','biweekly','monthly')),
  bank_or_mobile_money text,
  payment_account text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (business_id, employee_code),
  unique (id,business_id),
  foreign key (branch_id,business_id) references public.branches(id,business_id)
);
create index if not exists employees_business_status_idx
  on public.employees(business_id,employment_status,full_name);

create table if not exists public.payroll_runs (
  id uuid primary key default gen_random_uuid(),
  business_id uuid not null references public.businesses(id) on delete cascade,
  period_start date not null,
  period_end date not null,
  pay_date date not null,
  status text not null default 'draft'
    check (status in ('draft','approved','paid','voided')),
  gross_total numeric(18,2) not null default 0 check (gross_total >= 0),
  deduction_total numeric(18,2) not null default 0 check (deduction_total >= 0),
  net_total numeric(18,2) not null default 0 check (net_total >= 0),
  created_by uuid default auth.uid() references auth.users(id),
  approved_by uuid references auth.users(id),
  approved_at timestamptz,
  paid_at timestamptz,
  created_at timestamptz not null default now(),
  check (period_end >= period_start),
  check (net_total = gross_total - deduction_total),
  unique (id,business_id)
);
create table if not exists public.payroll_items (
  id uuid primary key default gen_random_uuid(),
  business_id uuid not null,
  payroll_run_id uuid not null,
  employee_id uuid not null,
  gross_pay numeric(18,2) not null check (gross_pay >= 0),
  tax_deduction numeric(18,2) not null default 0 check (tax_deduction >= 0),
  other_deductions numeric(18,2) not null default 0 check (other_deductions >= 0),
  net_pay numeric(18,2) generated always as (gross_pay-tax_deduction-other_deductions) stored,
  payment_reference text,
  payment_status text not null default 'pending'
    check (payment_status in ('pending','paid','failed')),
  created_at timestamptz not null default now(),
  foreign key (payroll_run_id,business_id)
    references public.payroll_runs(id,business_id) on delete cascade,
  foreign key (employee_id,business_id)
    references public.employees(id,business_id) on delete restrict,
  check (gross_pay >= tax_deduction + other_deductions)
);
create unique index if not exists payroll_items_run_employee_uidx
  on public.payroll_items(payroll_run_id,employee_id);
create index if not exists payroll_runs_business_period_idx
  on public.payroll_runs(business_id,period_start desc);

-- 2) Customer loyalty ledger. Points are immutable earn/redeem/adjustment entries.
create table if not exists public.customer_loyalty_accounts (
  id uuid primary key default gen_random_uuid(),
  business_id uuid not null,
  customer_id uuid not null,
  points_balance bigint not null default 0 check (points_balance >= 0),
  lifetime_points bigint not null default 0 check (lifetime_points >= 0),
  tier text not null default 'standard',
  updated_at timestamptz not null default now(),
  unique (business_id,customer_id),
  foreign key (customer_id,business_id)
    references public.customers(id,business_id) on delete cascade
);
create table if not exists public.customer_loyalty_ledger (
  id uuid primary key default gen_random_uuid(),
  business_id uuid not null,
  customer_id uuid not null,
  points_delta bigint not null check (points_delta <> 0),
  entry_type text not null check (entry_type in ('earned','redeemed','adjustment','expired')),
  source_reference text,
  note text,
  created_by uuid default auth.uid() references auth.users(id),
  created_at timestamptz not null default now(),
  foreign key (customer_id,business_id)
    references public.customers(id,business_id) on delete cascade
);
create index if not exists loyalty_ledger_customer_date_idx
  on public.customer_loyalty_ledger(business_id,customer_id,created_at desc);

-- 3) Online ordering foundation. Public storefront exposure is controlled by
--    is_published and stock visibility; order rows remain private to the business.
create table if not exists public.online_storefronts (
  id uuid primary key default gen_random_uuid(),
  business_id uuid not null unique references public.businesses(id) on delete cascade,
  slug text not null unique check (slug ~ '^[a-z0-9][a-z0-9-]{2,59}$'),
  display_name text not null,
  description text,
  contact_phone text,
  contact_email text,
  is_published boolean not null default false,
  accepts_orders boolean not null default false,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
create table if not exists public.online_store_products (
  id uuid primary key default gen_random_uuid(),
  business_id uuid not null,
  product_id uuid not null,
  is_published boolean not null default false,
  online_price numeric(18,2) check (online_price >= 0),
  description text,
  created_at timestamptz not null default now(),
  unique (business_id,product_id),
  foreign key (product_id,business_id)
    references public.products(id,business_id) on delete cascade
);
create table if not exists public.online_orders (
  id uuid primary key default gen_random_uuid(),
  business_id uuid not null references public.businesses(id) on delete cascade,
  order_number text not null,
  customer_id uuid,
  customer_name text not null,
  customer_phone text not null,
  customer_email text,
  delivery_address text,
  order_status text not null default 'received'
    check (order_status in ('received','confirmed','processing','ready','dispatched','completed','cancelled')),
  payment_status text not null default 'unpaid'
    check (payment_status in ('unpaid','pending','paid','refunded')),
  subtotal numeric(18,2) not null check (subtotal >= 0),
  delivery_fee numeric(18,2) not null default 0 check (delivery_fee >= 0),
  total numeric(18,2) not null check (total = subtotal + delivery_fee),
  source text not null default 'online',
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (business_id,order_number),
  unique (id,business_id),
  foreign key (customer_id,business_id)
    references public.customers(id,business_id) on delete set null (customer_id)
);
create table if not exists public.online_order_items (
  id uuid primary key default gen_random_uuid(),
  business_id uuid not null,
  order_id uuid not null,
  product_id uuid not null,
  product_name text not null,
  quantity numeric(18,3) not null check (quantity > 0),
  unit_price numeric(18,2) not null check (unit_price >= 0),
  line_total numeric(18,2) not null check (line_total = quantity * unit_price),
  foreign key (order_id,business_id)
    references public.online_orders(id,business_id) on delete cascade,
  foreign key (product_id,business_id)
    references public.products(id,business_id) on delete restrict
);
create index if not exists online_orders_business_status_date_idx
  on public.online_orders(business_id,order_status,created_at desc);

-- 4) Supplier collaboration and purchase requests. A supplier portal user is
--    explicitly linked to one supplier; supplier users cannot browse other tenants.
create table if not exists public.supplier_portal_members (
  business_id uuid not null,
  supplier_id uuid not null,
  user_id uuid not null references auth.users(id) on delete cascade,
  is_active boolean not null default true,
  invited_by uuid references auth.users(id),
  created_at timestamptz not null default now(),
  primary key (business_id,supplier_id,user_id),
  foreign key (supplier_id,business_id)
    references public.suppliers(id,business_id) on delete cascade
);
create table if not exists public.supplier_purchase_requests (
  id uuid primary key default gen_random_uuid(),
  business_id uuid not null,
  supplier_id uuid not null,
  request_number text not null,
  status text not null default 'sent'
    check (status in ('draft','sent','acknowledged','partially_fulfilled','fulfilled','cancelled')),
  requested_date date not null default current_date,
  expected_date date,
  notes text,
  created_by uuid default auth.uid() references auth.users(id),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (business_id,request_number),
  unique (id,business_id),
  foreign key (supplier_id,business_id)
    references public.suppliers(id,business_id) on delete restrict
);
create table if not exists public.supplier_purchase_request_items (
  id uuid primary key default gen_random_uuid(),
  business_id uuid not null,
  request_id uuid not null,
  product_id uuid not null,
  quantity_requested numeric(18,3) not null check (quantity_requested > 0),
  quantity_confirmed numeric(18,3) not null default 0 check (quantity_confirmed >= 0),
  unit_cost numeric(18,2) check (unit_cost >= 0),
  notes text,
  foreign key (request_id,business_id)
    references public.supplier_purchase_requests(id,business_id) on delete cascade,
  foreign key (product_id,business_id)
    references public.products(id,business_id) on delete restrict,
  check (quantity_confirmed <= quantity_requested)
);

-- 5) Optional business directory / marketplace listings. No customer or financial
--    records are exposed through this catalogue.
create table if not exists public.business_marketplace_listings (
  id uuid primary key default gen_random_uuid(),
  business_id uuid not null unique references public.businesses(id) on delete cascade,
  public_name text not null,
  category text not null,
  summary text not null,
  contact_phone text,
  contact_email text,
  website_url text,
  is_published boolean not null default false,
  approved_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

-- 6) Franchise management is layered on existing branches; it does not duplicate them.
create table if not exists public.franchise_agreements (
  id uuid primary key default gen_random_uuid(),
  business_id uuid not null references public.businesses(id) on delete cascade,
  franchisee_name text not null,
  franchisee_email text,
  territory text,
  agreement_reference text not null,
  start_date date not null,
  end_date date,
  royalty_rate numeric(7,4) not null default 0 check (royalty_rate between 0 and 100),
  status text not null default 'draft'
    check (status in ('draft','active','suspended','expired','terminated')),
  notes text,
  created_by uuid default auth.uid() references auth.users(id),
  created_at timestamptz not null default now(),
  unique (business_id,agreement_reference),
  unique (id,business_id),
  check (end_date is null or end_date >= start_date)
);
create table if not exists public.franchise_locations (
  business_id uuid not null,
  agreement_id uuid not null,
  branch_id uuid not null,
  created_at timestamptz not null default now(),
  primary key (agreement_id,branch_id),
  foreign key (agreement_id,business_id)
    references public.franchise_agreements(id,business_id) on delete cascade,
  foreign key (branch_id,business_id)
    references public.branches(id,business_id) on delete restrict
);

-- Consistent tenant security for all business-owned records.
do $$
declare t text;
begin
  foreach t in array array[
    'employees','payroll_runs','payroll_items',
    'customer_loyalty_accounts','customer_loyalty_ledger',
    'online_storefronts','online_store_products','online_orders','online_order_items',
    'supplier_portal_members','supplier_purchase_requests','supplier_purchase_request_items',
    'business_marketplace_listings','franchise_agreements','franchise_locations'
  ] loop
    execute format('alter table public.%I enable row level security',t);
    execute format('revoke all on public.%I from anon, public',t);
    execute format('grant select, insert, update, delete on public.%I to authenticated',t);
  end loop;
end $$;

-- Staff and payroll: owner/admin/accountant; managers can maintain staff profiles only.
drop policy if exists employees_member_read on public.employees;
create policy employees_member_read on public.employees for select to authenticated
using (public.has_business_role(business_id,array['owner','admin','manager','accountant']::public.business_role[]));
drop policy if exists employees_manage on public.employees;
create policy employees_manage on public.employees for all to authenticated
using (public.has_business_role(business_id,array['owner','admin','manager']::public.business_role[]))
with check (public.has_business_role(business_id,array['owner','admin','manager']::public.business_role[]));
drop policy if exists payroll_runs_finance on public.payroll_runs;
create policy payroll_runs_finance on public.payroll_runs for all to authenticated
using (public.has_business_role(business_id,array['owner','admin','accountant']::public.business_role[]))
with check (public.has_business_role(business_id,array['owner','admin','accountant']::public.business_role[]));
drop policy if exists payroll_items_finance on public.payroll_items;
create policy payroll_items_finance on public.payroll_items for all to authenticated
using (public.has_business_role(business_id,array['owner','admin','accountant']::public.business_role[]))
with check (public.has_business_role(business_id,array['owner','admin','accountant']::public.business_role[]));

-- Loyalty: staff who can serve customers may read and post ledger activity.
drop policy if exists loyalty_accounts_staff on public.customer_loyalty_accounts;
create policy loyalty_accounts_staff on public.customer_loyalty_accounts for all to authenticated
using (public.has_business_role(business_id,array['owner','admin','manager','cashier']::public.business_role[]))
with check (public.has_business_role(business_id,array['owner','admin','manager','cashier']::public.business_role[]));
drop policy if exists loyalty_ledger_staff on public.customer_loyalty_ledger;
create policy loyalty_ledger_staff on public.customer_loyalty_ledger for all to authenticated
using (public.has_business_role(business_id,array['owner','admin','manager','cashier']::public.business_role[]))
with check (public.has_business_role(business_id,array['owner','admin','manager','cashier']::public.business_role[]));

-- Storefront and orders are controlled by the business team. Anonymous access is
-- deliberately not granted here; public ordering must go through a reviewed RPC/API.
drop policy if exists storefront_admin on public.online_storefronts;
create policy storefront_admin on public.online_storefronts for all to authenticated
using (public.has_business_role(business_id,array['owner','admin','manager']::public.business_role[]))
with check (public.has_business_role(business_id,array['owner','admin','manager']::public.business_role[]));
drop policy if exists online_products_staff on public.online_store_products;
create policy online_products_staff on public.online_store_products for all to authenticated
using (public.has_business_role(business_id,array['owner','admin','manager','storekeeper']::public.business_role[]))
with check (public.has_business_role(business_id,array['owner','admin','manager','storekeeper']::public.business_role[]));
drop policy if exists online_orders_staff on public.online_orders;
create policy online_orders_staff on public.online_orders for all to authenticated
using (public.has_business_role(business_id,array['owner','admin','manager','cashier']::public.business_role[]))
with check (public.has_business_role(business_id,array['owner','admin','manager','cashier']::public.business_role[]));
drop policy if exists online_order_items_staff on public.online_order_items;
create policy online_order_items_staff on public.online_order_items for all to authenticated
using (public.has_business_role(business_id,array['owner','admin','manager','cashier']::public.business_role[]))
with check (public.has_business_role(business_id,array['owner','admin','manager','cashier']::public.business_role[]));

-- Supplier portal members may see only their own supplier's requests; business staff
-- manage invitations and requests. No direct supplier portal access to other tables.
drop policy if exists supplier_portal_member_manage on public.supplier_portal_members;
create policy supplier_portal_member_manage on public.supplier_portal_members for all to authenticated
using (public.has_business_role(business_id,array['owner','admin','manager','accountant']::public.business_role[]))
with check (public.has_business_role(business_id,array['owner','admin','manager','accountant']::public.business_role[]));
drop policy if exists supplier_requests_business_staff on public.supplier_purchase_requests;
create policy supplier_requests_business_staff on public.supplier_purchase_requests for all to authenticated
using (public.has_business_role(business_id,array['owner','admin','manager','storekeeper','accountant']::public.business_role[]))
with check (public.has_business_role(business_id,array['owner','admin','manager','storekeeper','accountant']::public.business_role[]));
drop policy if exists supplier_requests_linked_portal on public.supplier_purchase_requests;
create policy supplier_requests_linked_portal on public.supplier_purchase_requests for select to authenticated
using (exists (
  select 1 from public.supplier_portal_members p
  where p.business_id=supplier_purchase_requests.business_id
    and p.supplier_id=supplier_purchase_requests.supplier_id
    and p.user_id=auth.uid() and p.is_active
));
drop policy if exists supplier_request_items_staff on public.supplier_purchase_request_items;
create policy supplier_request_items_staff on public.supplier_purchase_request_items for all to authenticated
using (public.has_business_role(business_id,array['owner','admin','manager','storekeeper','accountant']::public.business_role[]))
with check (public.has_business_role(business_id,array['owner','admin','manager','storekeeper','accountant']::public.business_role[]));
drop policy if exists supplier_request_items_linked_portal on public.supplier_purchase_request_items;
create policy supplier_request_items_linked_portal on public.supplier_purchase_request_items for select to authenticated
using (exists (
  select 1 from public.supplier_purchase_requests r
  join public.supplier_portal_members p
    on p.business_id=r.business_id and p.supplier_id=r.supplier_id
  where r.id=supplier_purchase_request_items.request_id
    and r.business_id=supplier_purchase_request_items.business_id
    and p.user_id=auth.uid() and p.is_active
));

-- Marketplace listings are private until a deliberate public publishing layer is added.
drop policy if exists marketplace_listing_admin on public.business_marketplace_listings;
create policy marketplace_listing_admin on public.business_marketplace_listings for all to authenticated
using (public.has_business_role(business_id,array['owner','admin']::public.business_role[]))
with check (public.has_business_role(business_id,array['owner','admin']::public.business_role[]));

-- Franchise contracts and location assignments are owner/admin controlled.
drop policy if exists franchise_agreements_admin on public.franchise_agreements;
create policy franchise_agreements_admin on public.franchise_agreements for all to authenticated
using (public.has_business_role(business_id,array['owner','admin']::public.business_role[]))
with check (public.has_business_role(business_id,array['owner','admin']::public.business_role[]));
drop policy if exists franchise_locations_admin on public.franchise_locations;
create policy franchise_locations_admin on public.franchise_locations for all to authenticated
using (public.has_business_role(business_id,array['owner','admin']::public.business_role[]))
with check (public.has_business_role(business_id,array['owner','admin']::public.business_role[]));

-- Record the new module catalogue entries for existing and future businesses.
insert into public.business_industry_modules(business_id,module_key,is_enabled)
select b.id,m.module_key,false
from public.businesses b
cross join (values
 ('payroll'),('customer_loyalty'),('online_store'),('supplier_portal'),
 ('business_marketplace'),('franchise_management')
) as m(module_key)
on conflict (business_id,module_key) do nothing;

commit;
