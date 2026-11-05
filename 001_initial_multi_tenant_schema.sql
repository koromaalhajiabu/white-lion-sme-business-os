-- White Lion SME Business Operating System
-- Initial multi-tenant foundation. Review in a test Supabase project before production.
-- Run once in Supabase SQL Editor or through the Supabase CLI migration workflow.

begin;

create extension if not exists pgcrypto;

create type public.business_role as enum
  ('owner','admin','manager','cashier','storekeeper','accountant','viewer');

create type public.transaction_status as enum ('draft','posted','voided');

create table public.profiles (
  id uuid primary key references auth.users(id) on delete cascade,
  full_name text not null default '',
  phone text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table public.businesses (
  id uuid primary key default gen_random_uuid(),
  name text not null,
  industry text not null default 'Multi-industry',
  currency_code text not null default 'SLE' check (currency_code ~ '^[A-Z]{3}$'),
  owner_user_id uuid not null references auth.users(id),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table public.business_members (
  business_id uuid not null references public.businesses(id) on delete cascade,
  user_id uuid not null references auth.users(id) on delete cascade,
  role public.business_role not null default 'viewer',
  is_active boolean not null default true,
  invited_by uuid references auth.users(id),
  created_at timestamptz not null default now(),
  primary key (business_id, user_id)
);

create table public.branches (
  id uuid primary key default gen_random_uuid(),
  business_id uuid not null references public.businesses(id) on delete cascade,
  name text not null,
  address text,
  is_active boolean not null default true,
  created_at timestamptz not null default now(),
  unique (business_id, name),
  unique (id, business_id)
);

create table public.customers (
  id uuid primary key default gen_random_uuid(),
  business_id uuid not null references public.businesses(id) on delete cascade,
  name text not null,
  phone text,
  email text,
  address text,
  notes text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (id, business_id)
);

create table public.suppliers (
  id uuid primary key default gen_random_uuid(),
  business_id uuid not null references public.businesses(id) on delete cascade,
  name text not null,
  phone text,
  email text,
  address text,
  notes text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (id, business_id)
);

create table public.products (
  id uuid primary key default gen_random_uuid(),
  business_id uuid not null references public.businesses(id) on delete cascade,
  sku text,
  name text not null,
  category text,
  unit text not null default 'unit',
  cost_price numeric(18,2) not null default 0 check (cost_price >= 0),
  selling_price numeric(18,2) not null default 0 check (selling_price >= 0),
  reorder_level numeric(18,3) not null default 0 check (reorder_level >= 0),
  is_active boolean not null default true,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (id, business_id),
  unique (business_id, sku)
);

create table public.branch_inventory (
  business_id uuid not null references public.businesses(id) on delete cascade,
  branch_id uuid not null,
  product_id uuid not null,
  quantity_on_hand numeric(18,3) not null default 0 check (quantity_on_hand >= 0),
  updated_at timestamptz not null default now(),
  primary key (branch_id, product_id),
  foreign key (branch_id, business_id) references public.branches(id, business_id) on delete cascade,
  foreign key (product_id, business_id) references public.products(id, business_id) on delete cascade
);

create table public.sales (
  id uuid primary key default gen_random_uuid(),
  business_id uuid not null references public.businesses(id) on delete cascade,
  branch_id uuid not null,
  customer_id uuid,
  reference text not null,
  status public.transaction_status not null default 'posted',
  subtotal numeric(18,2) not null check (subtotal >= 0),
  discount numeric(18,2) not null default 0 check (discount >= 0),
  total numeric(18,2) not null check (total >= 0),
  amount_paid numeric(18,2) not null default 0 check (amount_paid >= 0),
  payment_method text not null default 'cash',
  created_by uuid not null default auth.uid() references auth.users(id),
  created_at timestamptz not null default now(),
  unique (business_id, reference),
  unique (id, business_id),
  foreign key (branch_id, business_id) references public.branches(id, business_id),
  foreign key (customer_id, business_id) references public.customers(id, business_id)
);

create table public.sale_items (
  id uuid primary key default gen_random_uuid(),
  business_id uuid not null references public.businesses(id) on delete cascade,
  sale_id uuid not null,
  product_id uuid not null,
  quantity numeric(18,3) not null check (quantity > 0),
  unit_price numeric(18,2) not null check (unit_price >= 0),
  unit_cost numeric(18,2) not null check (unit_cost >= 0),
  line_total numeric(18,2) not null check (line_total >= 0),
  foreign key (sale_id, business_id) references public.sales(id, business_id) on delete cascade,
  foreign key (product_id, business_id) references public.products(id, business_id)
);

create table public.purchases (
  id uuid primary key default gen_random_uuid(),
  business_id uuid not null references public.businesses(id) on delete cascade,
  branch_id uuid not null,
  supplier_id uuid,
  reference text not null,
  status public.transaction_status not null default 'posted',
  total numeric(18,2) not null check (total >= 0),
  amount_paid numeric(18,2) not null default 0 check (amount_paid >= 0),
  created_by uuid not null default auth.uid() references auth.users(id),
  created_at timestamptz not null default now(),
  unique (business_id, reference),
  unique (id, business_id),
  foreign key (branch_id, business_id) references public.branches(id, business_id),
  foreign key (supplier_id, business_id) references public.suppliers(id, business_id)
);

create table public.purchase_items (
  id uuid primary key default gen_random_uuid(),
  business_id uuid not null references public.businesses(id) on delete cascade,
  purchase_id uuid not null,
  product_id uuid not null,
  quantity numeric(18,3) not null check (quantity > 0),
  unit_cost numeric(18,2) not null check (unit_cost >= 0),
  line_total numeric(18,2) not null check (line_total >= 0),
  foreign key (purchase_id, business_id) references public.purchases(id, business_id) on delete cascade,
  foreign key (product_id, business_id) references public.products(id, business_id)
);

create table public.inventory_movements (
  id uuid primary key default gen_random_uuid(),
  business_id uuid not null references public.businesses(id) on delete cascade,
  branch_id uuid not null,
  product_id uuid not null,
  movement_type text not null check (movement_type in ('opening','sale','purchase','adjustment','return','transfer_in','transfer_out','reversal')),
  quantity_delta numeric(18,3) not null check (quantity_delta <> 0),
  reference_table text,
  reference_id uuid,
  note text,
  created_by uuid default auth.uid() references auth.users(id),
  created_at timestamptz not null default now(),
  foreign key (branch_id, business_id) references public.branches(id, business_id),
  foreign key (product_id, business_id) references public.products(id, business_id)
);

create table public.expenses (
  id uuid primary key default gen_random_uuid(),
  business_id uuid not null references public.businesses(id) on delete cascade,
  branch_id uuid,
  category text not null,
  description text not null,
  amount numeric(18,2) not null check (amount > 0),
  payment_method text not null default 'cash',
  expense_date date not null default current_date,
  created_by uuid not null default auth.uid() references auth.users(id),
  created_at timestamptz not null default now(),
  foreign key (branch_id, business_id) references public.branches(id, business_id)
);

create table public.audit_logs (
  id bigint generated always as identity primary key,
  business_id uuid not null references public.businesses(id) on delete cascade,
  actor_user_id uuid default auth.uid() references auth.users(id),
  action text not null,
  entity_table text not null,
  entity_id text,
  details jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now()
);

create index on public.business_members(user_id, is_active);
create index on public.products(business_id, name);
create index on public.sales(business_id, created_at desc);
create index on public.purchases(business_id, created_at desc);
create index on public.inventory_movements(business_id, product_id, created_at desc);
create index on public.audit_logs(business_id, created_at desc);

-- SECURITY DEFINER membership helpers avoid recursive RLS lookups on business_members.
create or replace function public.is_business_member(p_business_id uuid)
returns boolean language sql stable security definer
set search_path = public, auth
as $$
  select exists (
    select 1 from public.business_members m
    where m.business_id = p_business_id
      and m.user_id = auth.uid()
      and m.is_active = true
  );
$$;

create or replace function public.has_business_role(p_business_id uuid, p_roles public.business_role[])
returns boolean language sql stable security definer
set search_path = public, auth
as $$
  select exists (
    select 1 from public.business_members m
    where m.business_id = p_business_id
      and m.user_id = auth.uid()
      and m.is_active = true
      and m.role = any(p_roles)
  );
$$;

revoke all on function public.is_business_member(uuid) from public;
revoke all on function public.has_business_role(uuid, public.business_role[]) from public;
grant execute on function public.is_business_member(uuid) to authenticated;
grant execute on function public.has_business_role(uuid, public.business_role[]) to authenticated;

-- New user profile creation.
create or replace function public.handle_new_user()
returns trigger language plpgsql security definer
set search_path = public
as $$
begin
  insert into public.profiles(id, full_name)
  values (new.id, coalesce(new.raw_user_meta_data->>'full_name',''));
  return new;
end;
$$;

drop trigger if exists on_auth_user_created on auth.users;
create trigger on_auth_user_created
after insert on auth.users
for each row execute procedure public.handle_new_user();

-- Business creation also creates the owner membership and a default branch.
create or replace function public.create_business(
  p_name text,
  p_industry text default 'Multi-industry',
  p_currency_code text default 'SLE'
) returns uuid
language plpgsql security definer
set search_path = public, auth
as $$
declare v_business_id uuid;
begin
  if auth.uid() is null then raise exception 'Authentication required'; end if;
  if length(trim(coalesce(p_name,''))) < 2 then raise exception 'Business name is required'; end if;
  insert into public.businesses(name, industry, currency_code, owner_user_id)
  values (trim(p_name), coalesce(nullif(trim(p_industry),''),'Multi-industry'),
          upper(coalesce(nullif(trim(p_currency_code),''),'SLE')), auth.uid())
  returning id into v_business_id;
  insert into public.business_members(business_id,user_id,role)
  values (v_business_id, auth.uid(), 'owner');
  insert into public.branches(business_id,name) values (v_business_id,'Main Branch');
  insert into public.audit_logs(business_id,action,entity_table,entity_id)
  values (v_business_id,'business_created','businesses',v_business_id::text);
  return v_business_id;
end;
$$;
grant execute on function public.create_business(text,text,text) to authenticated;

-- Atomic sale posting. Stock and sale rows commit or roll back together.
create or replace function public.post_sale(
  p_business_id uuid,
  p_branch_id uuid,
  p_reference text,
  p_items jsonb,
  p_customer_id uuid default null,
  p_discount numeric default 0,
  p_amount_paid numeric default 0,
  p_payment_method text default 'cash'
) returns uuid
language plpgsql security definer
set search_path = public, auth
as $$
declare
  v_sale_id uuid := gen_random_uuid();
  v_item jsonb;
  v_product_id uuid;
  v_qty numeric(18,3);
  v_price numeric(18,2);
  v_cost numeric(18,2);
  v_stock numeric(18,3);
  v_subtotal numeric(18,2) := 0;
  v_total numeric(18,2);
  v_line numeric(18,2);
  v_role public.business_role;
begin
  if auth.uid() is null then raise exception 'Authentication required'; end if;
  if not public.has_business_role(p_business_id, array['owner','admin','manager','cashier']::public.business_role[]) then
    raise exception 'Not authorised to record sales';
  end if;
  if jsonb_typeof(p_items) <> 'array' or jsonb_array_length(p_items) = 0 then
    raise exception 'At least one sale item is required';
  end if;
  if trim(coalesce(p_reference,'')) = '' then raise exception 'Sale reference is required'; end if;
  if p_discount < 0 or p_amount_paid < 0 then raise exception 'Invalid discount or payment'; end if;

  perform 1 from public.branches where id=p_branch_id and business_id=p_business_id and is_active=true;
  if not found then raise exception 'Invalid branch'; end if;

  for v_item in select value from jsonb_array_elements(p_items) loop
    v_product_id := (v_item->>'product_id')::uuid;
    v_qty := (v_item->>'quantity')::numeric;
    if v_qty <= 0 then raise exception 'Sale quantity must be positive'; end if;
    select selling_price, cost_price into v_price, v_cost
      from public.products where id=v_product_id and business_id=p_business_id and is_active=true;
    if not found then raise exception 'Product not found or inactive'; end if;
    select quantity_on_hand into v_stock from public.branch_inventory
      where branch_id=p_branch_id and product_id=v_product_id and business_id=p_business_id
      for update;
    if not found or v_stock < v_qty then raise exception 'Insufficient stock for product %', v_product_id; end if;
    v_line := round(v_qty * coalesce((v_item->>'unit_price')::numeric, v_price),2);
    if v_line < 0 then raise exception 'Invalid line amount'; end if;
    v_subtotal := v_subtotal + v_line;
  end loop;

  v_total := greatest(v_subtotal - p_discount,0);
  if p_amount_paid > v_total then raise exception 'Payment cannot exceed sale total'; end if;

  insert into public.sales(id,business_id,branch_id,customer_id,reference,subtotal,discount,total,amount_paid,payment_method)
  values(v_sale_id,p_business_id,p_branch_id,p_customer_id,trim(p_reference),v_subtotal,p_discount,v_total,p_amount_paid,coalesce(p_payment_method,'cash'));

  for v_item in select value from jsonb_array_elements(p_items) loop
    v_product_id := (v_item->>'product_id')::uuid;
    v_qty := (v_item->>'quantity')::numeric;
    select selling_price,cost_price into v_price,v_cost from public.products
      where id=v_product_id and business_id=p_business_id;
    v_price := coalesce((v_item->>'unit_price')::numeric,v_price);
    v_line := round(v_qty*v_price,2);
    insert into public.sale_items(business_id,sale_id,product_id,quantity,unit_price,unit_cost,line_total)
      values(p_business_id,v_sale_id,v_product_id,v_qty,v_price,v_cost,v_line);
    update public.branch_inventory set quantity_on_hand=quantity_on_hand-v_qty,updated_at=now()
      where branch_id=p_branch_id and product_id=v_product_id and business_id=p_business_id;
    insert into public.inventory_movements(business_id,branch_id,product_id,movement_type,quantity_delta,reference_table,reference_id)
      values(p_business_id,p_branch_id,v_product_id,'sale',-v_qty,'sales',v_sale_id);
  end loop;

  insert into public.audit_logs(business_id,action,entity_table,entity_id,details)
    values(p_business_id,'sale_posted','sales',v_sale_id::text,jsonb_build_object('reference',p_reference,'total',v_total));
  return v_sale_id;
end;
$$;
grant execute on function public.post_sale(uuid,uuid,text,jsonb,uuid,numeric,numeric,text) to authenticated;

-- Atomic purchase receipt. Adds stock and records movements.
create or replace function public.post_purchase(
  p_business_id uuid,
  p_branch_id uuid,
  p_reference text,
  p_items jsonb,
  p_supplier_id uuid default null,
  p_amount_paid numeric default 0
) returns uuid
language plpgsql security definer
set search_path = public, auth
as $$
declare
  v_purchase_id uuid := gen_random_uuid();
  v_item jsonb;
  v_product_id uuid;
  v_qty numeric(18,3);
  v_cost numeric(18,2);
  v_line numeric(18,2);
  v_total numeric(18,2) := 0;
begin
  if auth.uid() is null then raise exception 'Authentication required'; end if;
  if not public.has_business_role(p_business_id, array['owner','admin','manager','storekeeper','accountant']::public.business_role[]) then
    raise exception 'Not authorised to record purchases';
  end if;
  if jsonb_typeof(p_items) <> 'array' or jsonb_array_length(p_items)=0 then raise exception 'At least one purchase item is required'; end if;
  if trim(coalesce(p_reference,''))='' then raise exception 'Purchase reference is required'; end if;
  if p_amount_paid < 0 then raise exception 'Invalid payment'; end if;
  perform 1 from public.branches where id=p_branch_id and business_id=p_business_id and is_active=true;
  if not found then raise exception 'Invalid branch'; end if;

  for v_item in select value from jsonb_array_elements(p_items) loop
    v_product_id := (v_item->>'product_id')::uuid;
    v_qty := (v_item->>'quantity')::numeric;
    v_cost := (v_item->>'unit_cost')::numeric;
    if v_qty<=0 or v_cost<0 then raise exception 'Invalid purchase quantity or cost'; end if;
    perform 1 from public.products where id=v_product_id and business_id=p_business_id and is_active=true;
    if not found then raise exception 'Product not found or inactive'; end if;
    v_total := v_total + round(v_qty*v_cost,2);
  end loop;
  if p_amount_paid > v_total then raise exception 'Payment cannot exceed purchase total'; end if;

  insert into public.purchases(id,business_id,branch_id,supplier_id,reference,total,amount_paid)
    values(v_purchase_id,p_business_id,p_branch_id,p_supplier_id,trim(p_reference),v_total,p_amount_paid);

  for v_item in select value from jsonb_array_elements(p_items) loop
    v_product_id := (v_item->>'product_id')::uuid;
    v_qty := (v_item->>'quantity')::numeric;
    v_cost := (v_item->>'unit_cost')::numeric;
    v_line := round(v_qty*v_cost,2);
    insert into public.purchase_items(business_id,purchase_id,product_id,quantity,unit_cost,line_total)
      values(p_business_id,v_purchase_id,v_product_id,v_qty,v_cost,v_line);
    insert into public.branch_inventory(business_id,branch_id,product_id,quantity_on_hand)
      values(p_business_id,p_branch_id,v_product_id,v_qty)
      on conflict(branch_id,product_id) do update
        set quantity_on_hand=public.branch_inventory.quantity_on_hand+excluded.quantity_on_hand,updated_at=now();
    insert into public.inventory_movements(business_id,branch_id,product_id,movement_type,quantity_delta,reference_table,reference_id)
      values(p_business_id,p_branch_id,v_product_id,'purchase',v_qty,'purchases',v_purchase_id);
  end loop;

  insert into public.audit_logs(business_id,action,entity_table,entity_id,details)
    values(p_business_id,'purchase_posted','purchases',v_purchase_id::text,jsonb_build_object('reference',p_reference,'total',v_total));
  return v_purchase_id;
end;
$$;
grant execute on function public.post_purchase(uuid,uuid,text,jsonb,uuid,numeric) to authenticated;

-- Enable RLS everywhere exposed to authenticated clients.
do $$
declare t text;
begin
  foreach t in array array['profiles','businesses','business_members','branches','customers','suppliers','products','branch_inventory','sales','sale_items','purchases','purchase_items','inventory_movements','expenses','audit_logs'] loop
    execute format('alter table public.%I enable row level security',t);
  end loop;
end $$;

create policy "profiles_select_self" on public.profiles for select to authenticated using (id=auth.uid());
create policy "profiles_update_self" on public.profiles for update to authenticated using (id=auth.uid()) with check (id=auth.uid());

create policy "business_select_member" on public.businesses for select to authenticated using (public.is_business_member(id));
create policy "business_update_admin" on public.businesses for update to authenticated using (public.has_business_role(id,array['owner','admin']::public.business_role[])) with check (public.has_business_role(id,array['owner','admin']::public.business_role[]));

create policy "members_select_same_business" on public.business_members for select to authenticated using (public.is_business_member(business_id));
create policy "members_manage_admin" on public.business_members for all to authenticated
  using (public.has_business_role(business_id,array['owner','admin']::public.business_role[]))
  with check (public.has_business_role(business_id,array['owner','admin']::public.business_role[]));

create policy "branches_member_read" on public.branches for select to authenticated using (public.is_business_member(business_id));
create policy "branches_admin_write" on public.branches for all to authenticated
  using (public.has_business_role(business_id,array['owner','admin','manager']::public.business_role[]))
  with check (public.has_business_role(business_id,array['owner','admin','manager']::public.business_role[]));

create policy "customers_member_read" on public.customers for select to authenticated using (public.is_business_member(business_id));
create policy "customers_staff_write" on public.customers for all to authenticated
  using (public.has_business_role(business_id,array['owner','admin','manager','cashier']::public.business_role[]))
  with check (public.has_business_role(business_id,array['owner','admin','manager','cashier']::public.business_role[]));

create policy "suppliers_member_read" on public.suppliers for select to authenticated using (public.is_business_member(business_id));
create policy "suppliers_staff_write" on public.suppliers for all to authenticated
  using (public.has_business_role(business_id,array['owner','admin','manager','storekeeper','accountant']::public.business_role[]))
  with check (public.has_business_role(business_id,array['owner','admin','manager','storekeeper','accountant']::public.business_role[]));

create policy "products_member_read" on public.products for select to authenticated using (public.is_business_member(business_id));
create policy "products_admin_write" on public.products for all to authenticated
  using (public.has_business_role(business_id,array['owner','admin','manager','storekeeper']::public.business_role[]))
  with check (public.has_business_role(business_id,array['owner','admin','manager','storekeeper']::public.business_role[]));

create policy "inventory_member_read" on public.branch_inventory for select to authenticated using (public.is_business_member(business_id));
create policy "inventory_admin_write" on public.branch_inventory for all to authenticated
  using (public.has_business_role(business_id,array['owner','admin','manager','storekeeper']::public.business_role[]))
  with check (public.has_business_role(business_id,array['owner','admin','manager','storekeeper']::public.business_role[]));

create policy "sales_member_read" on public.sales for select to authenticated using (public.is_business_member(business_id));
create policy "sale_items_member_read" on public.sale_items for select to authenticated using (public.is_business_member(business_id));
create policy "purchases_member_read" on public.purchases for select to authenticated using (public.is_business_member(business_id));
create policy "purchase_items_member_read" on public.purchase_items for select to authenticated using (public.is_business_member(business_id));

create policy "movements_member_read" on public.inventory_movements for select to authenticated using (public.is_business_member(business_id));
create policy "expenses_member_read" on public.expenses for select to authenticated using (public.is_business_member(business_id));
create policy "expenses_staff_write" on public.expenses for insert to authenticated
  with check (public.has_business_role(business_id,array['owner','admin','manager','accountant']::public.business_role[]));
create policy "audit_member_read" on public.audit_logs for select to authenticated using (public.is_business_member(business_id));

-- No direct client-side writes to posted sales/purchases, line items, movements or audit logs.
-- Use post_sale() and post_purchase() RPCs for atomic transaction posting.

commit;
