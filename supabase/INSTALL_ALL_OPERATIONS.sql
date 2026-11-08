-- WHITE LION SME BUSINESS OPERATING SYSTEM
-- SINGLE INSTALLER: Branch-aware operations + finance + inventory controls
-- Prerequisite: migrations 001–009 must already be installed.
-- Run this entire file ONCE in Supabase SQL Editor.
-- This script applies migrations 010, 011 and 012 in one transaction.
-- Do not separately run migrations 010/011 if you run this installer.

begin;

-- MIGRATION 010: BRANCH-AWARE OPERATIONS
-- White Lion SME Business OS — Migration 010
-- Branch-scoped transaction posting, transfer rejection, and branch stock write controls.
-- Legacy transactions remain unchanged; new postings must name an active branch.

-- Extend transfer decisions without deleting or rewriting existing requests.
alter table public.branch_stock_transfers
  drop constraint if exists branch_stock_transfers_status_check;
alter table public.branch_stock_transfers
  add constraint branch_stock_transfers_status_check
  check (status in ('pending','completed','cancelled','rejected'));

alter table public.branch_stock_transfers
  add column if not exists rejected_by uuid null references auth.users(id) on delete set null,
  add column if not exists rejected_at timestamptz null,
  add column if not exists decision_note text null;

-- Replace every existing branch_inventory write policy. PostgreSQL policies are
-- permissive by default, so leaving an older broad ALL policy would bypass scope.
-- MIGRATION 012: RETAIL SALE ADJUSTMENTS
-- Keep sale subtotal, discount, tax and final total consistent across devices.
alter table public.offline_sales
  add column if not exists subtotal numeric(14,2) not null default 0 check (subtotal >= 0),
  add column if not exists discount numeric(14,2) not null default 0 check (discount >= 0),
  add column if not exists tax numeric(14,2) not null default 0 check (tax >= 0);

update public.offline_sales
set subtotal = total
where subtotal = 0 and discount = 0 and tax = 0 and total > 0;

create or replace function public.sync_branch_transaction(
  p_business_id uuid,
  p_branch_id uuid,
  p_event_id text,
  p_transaction_type text,
  p_transaction jsonb
) returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_role public.business_role;
  v_sale uuid;
  v_purchase uuid;
  v_item jsonb;
  v_product uuid;
  v_qty numeric;
  v_price numeric;
  v_total numeric := 0;
  v_header_total numeric;
  v_subtotal numeric;
  v_discount numeric := 0;
  v_tax numeric := 0;
  v_expected_total numeric;
  v_count integer := 0;
  v_client_transaction_id text;
  v_receipt text;
  v_group record;
begin
  if auth.uid() is null then raise exception 'Authentication required'; end if;
  if coalesce(trim(p_event_id),'') = '' then raise exception 'Transaction event ID is required'; end if;
  if p_transaction_type not in ('sales','purchases') then raise exception 'Unsupported transaction type'; end if;
  if jsonb_typeof(p_transaction->'items') <> 'array'
     or jsonb_array_length(p_transaction->'items') = 0 then
    raise exception 'Transaction must contain at least one item';
  end if;

  select bm.role into v_role
  from public.business_members bm
  where bm.business_id = p_business_id
    and bm.user_id = auth.uid()
    and bm.is_active = true;
  if not found or v_role is null then raise exception 'Active business membership required'; end if;
  if not public.has_business_role(p_business_id,array['owner','admin','manager','cashier','storekeeper']::public.business_role[]) then
    raise exception 'Active business membership and platform access required';
  end if;

  if v_role not in ('owner','admin','manager','cashier','storekeeper') then
    raise exception 'Your role cannot post sales or purchases';
  end if;
  if v_role = 'cashier' and p_transaction_type <> 'sales' then
    raise exception 'Cashiers may post sales only';
  end if;
  if v_role = 'storekeeper' and p_transaction_type <> 'purchases' then
    raise exception 'Storekeepers may post purchases only';
  end if;

  if not exists (
    select 1 from public.branches b
    where b.id = p_branch_id and b.business_id = p_business_id and b.is_active = true
  ) then raise exception 'Select an active branch belonging to this business'; end if;

  if v_role in ('cashier','storekeeper') and not exists (
    select 1 from public.branch_members bm
    where bm.business_id = p_business_id
      and bm.branch_id = p_branch_id
      and bm.user_id = auth.uid()
      and bm.is_active = true
  ) then raise exception 'You are not assigned to the selected branch'; end if;

  if exists (
    select 1 from public.offline_sync_receipts r
    where r.business_id = p_business_id and r.event_id = p_event_id
  ) then
    return jsonb_build_object('status','already_synced','processed',0);
  end if;

  v_client_transaction_id := nullif(trim(p_transaction->>'client_transaction_id'),'');
  if v_client_transaction_id is null then raise exception 'Client transaction ID is required'; end if;
  v_header_total := (p_transaction->>'total')::numeric;
  if v_header_total is null or v_header_total < 0 then raise exception 'Transaction total must be zero or greater'; end if;

  -- Validate every line and calculate the authoritative rounded total before writes.
  for v_item in select value from jsonb_array_elements(p_transaction->'items') loop
    select p.id into v_product
    from public.products p
    where p.business_id = p_business_id
      and p.client_record_id = v_item->>'product_client_record_id'
      and p.is_active = true;
    if v_product is null then raise exception 'A product is missing, inactive, or not synced to this workspace'; end if;

    v_qty := (v_item->>'quantity')::numeric;
    if v_qty is null or v_qty <= 0 then raise exception 'Every transaction quantity must be greater than zero'; end if;

    if p_transaction_type = 'sales' then
      v_price := (v_item->>'unit_price')::numeric;
    else
      v_price := (v_item->>'unit_cost')::numeric;
    end if;
    if v_price is null or v_price < 0 then raise exception 'Every transaction unit price must be zero or greater'; end if;

    v_total := v_total + round(v_qty * v_price, 2);
    v_count := v_count + 1;
  end loop;

  if p_transaction_type = 'sales' then
    -- Older clients omit adjustment fields; treat those sales as full-price sales.
    v_subtotal := round(coalesce(nullif(p_transaction->>'subtotal','')::numeric,v_total),2);
    v_discount := round(coalesce(nullif(p_transaction->>'discount','')::numeric,0),2);
    v_tax := round(coalesce(nullif(p_transaction->>'tax','')::numeric,0),2);
    if v_subtotal < 0 or v_discount < 0 or v_tax < 0 then
      raise exception 'Subtotal, discount and tax must be zero or greater';
    end if;
    if abs(v_subtotal-v_total) > 0.01 then
      raise exception 'Sale subtotal does not match its item totals (calculated %, supplied %)', v_total, v_subtotal;
    end if;
    if v_discount > v_subtotal then
      raise exception 'Sale discount cannot exceed subtotal';
    end if;
    v_expected_total := round(v_subtotal-v_discount+v_tax,2);
  else
    v_expected_total := v_total;
  end if;

  if abs(v_expected_total-v_header_total) > 0.01 then
    raise exception 'Transaction total does not match its calculated total (calculated %, supplied %)', v_expected_total, v_header_total;
  end if;

  -- Aggregate repeated product lines before checking/decrementing stock, preventing overselling.
  if p_transaction_type = 'sales' then
    for v_group in
      select p.id as product_id, sum((j.value->>'quantity')::numeric) as quantity,
             min(coalesce(nullif(j.value->>'product_name',''),p.name)) as product_name
      from jsonb_array_elements(p_transaction->'items') j(value)
      join public.products p
        on p.business_id = p_business_id
       and p.client_record_id = j.value->>'product_client_record_id'
       and p.is_active = true
      where coalesce((j.value->>'apply_stock')::boolean,true) = true
      group by p.id
      order by p.id
    loop
      update public.branch_inventory bi
      set quantity_on_hand = bi.quantity_on_hand - v_group.quantity,
          updated_at = now()
      where bi.business_id = p_business_id
        and bi.branch_id = p_branch_id
        and bi.product_id = v_group.product_id
        and bi.quantity_on_hand >= v_group.quantity;
      if not found then
        raise exception 'Insufficient stock at the selected branch for product %', v_group.product_name;
      end if;
      -- Keep tracked batch quantities aligned with POS stock consumption.
      perform public.consume_product_batches(
        p_business_id,p_branch_id,v_group.product_id,v_group.quantity
      );
    end loop;

    v_receipt := coalesce(nullif(p_transaction->>'receipt',''), 'WL-' || substr(p_event_id,1,12));
    insert into public.offline_sales(
      business_id,branch_id,client_transaction_id,receipt,transaction_date,
      customer_name,payment_method,subtotal,discount,tax,total
    ) values (
      p_business_id,p_branch_id,v_client_transaction_id,v_receipt,
      coalesce(nullif(p_transaction->>'transaction_date','')::date,current_date),
      nullif(p_transaction->>'customer_name',''),
      coalesce(nullif(p_transaction->>'payment_method',''),'cash'),
      v_subtotal,v_discount,v_tax,v_header_total
    ) returning id into v_sale;

    for v_item in select value from jsonb_array_elements(p_transaction->'items') loop
      select p.id into v_product
      from public.products p
      where p.business_id = p_business_id
        and p.client_record_id = v_item->>'product_client_record_id'
        and p.is_active = true;
      v_qty := (v_item->>'quantity')::numeric;
      v_price := (v_item->>'unit_price')::numeric;
      insert into public.offline_sale_items(
        business_id,sale_id,product_id,product_name,quantity,unit_price,line_total
      ) values (
        p_business_id,v_sale,v_product,
        coalesce(nullif(v_item->>'product_name',''),'Product'),
        v_qty,v_price,round(v_qty*v_price,2)
      );
    end loop;
  else
    -- Purchases add stock at the selected branch. Repeated lines are safely additive.
    insert into public.offline_purchases(
      business_id,branch_id,client_transaction_id,transaction_date,supplier_name,total
    ) values (
      p_business_id,p_branch_id,v_client_transaction_id,
      coalesce(nullif(p_transaction->>'transaction_date','')::date,current_date),
      nullif(p_transaction->>'supplier_name',''),v_total
    ) returning id into v_purchase;

    for v_item in select value from jsonb_array_elements(p_transaction->'items') loop
      select p.id into v_product
      from public.products p
      where p.business_id = p_business_id
        and p.client_record_id = v_item->>'product_client_record_id'
        and p.is_active = true;
      v_qty := (v_item->>'quantity')::numeric;
      v_price := (v_item->>'unit_cost')::numeric;

      if coalesce((v_item->>'apply_stock')::boolean,true) then
        insert into public.branch_inventory(business_id,branch_id,product_id,quantity_on_hand)
        values(p_business_id,p_branch_id,v_product,v_qty)
        on conflict(branch_id,product_id) do update
          set quantity_on_hand = public.branch_inventory.quantity_on_hand + excluded.quantity_on_hand,
              updated_at = now();
      end if;

      insert into public.offline_purchase_items(
        business_id,purchase_id,product_id,product_name,quantity,unit_cost,line_total
      ) values (
        p_business_id,v_purchase,v_product,
        coalesce(nullif(v_item->>'product_name',''),'Product'),
        v_qty,v_price,round(v_qty*v_price,2)
      );
    end loop;
  end if;

  insert into public.offline_sync_receipts(business_id,event_id,record_type,record_count)
  values(p_business_id,p_event_id,p_transaction_type,v_count);

  insert into public.audit_logs(business_id,actor_user_id,action,entity_table,entity_id,details)
  values(
    p_business_id,auth.uid(),'branch_' || p_transaction_type || '_posted',
    case when p_transaction_type='sales' then 'offline_sales' else 'offline_purchases' end,
    coalesce(v_sale,v_purchase)::text,
    jsonb_build_object(
      'branch_id',p_branch_id,'item_count',v_count,
      'subtotal',case when p_transaction_type='sales' then v_subtotal else v_total end,
      'discount',case when p_transaction_type='sales' then v_discount else 0 end,
      'tax',case when p_transaction_type='sales' then v_tax else 0 end,
      'total',v_header_total
    )
  );

  return jsonb_build_object(
    'status','synced','processed',v_count,
    'transaction_id',coalesce(v_sale,v_purchase),'branch_id',p_branch_id,'total',v_header_total
  );
end;
$$;


do $$
declare p record;
begin
  for p in
    select policyname from pg_policies
    where schemaname='public' and tablename='branch_inventory'
  loop
    execute format('drop policy %I on public.branch_inventory',p.policyname);
  end loop;
end;
$$;

create policy branch_inventory_member_read on public.branch_inventory
for select to authenticated
using(public.is_business_member(business_id));

-- Only owners/admins/managers have workspace-wide stock write access.
-- Storekeepers can write stock only for branches to which they are assigned.
create policy branch_inventory_manage on public.branch_inventory
for all to authenticated
using (
  public.has_business_role(business_id,array['owner','admin','manager']::public.business_role[])
  or (
    public.has_business_role(business_id,array['storekeeper']::public.business_role[])
    and exists(
      select 1 from public.branch_members bm
      where bm.business_id=branch_inventory.business_id
        and bm.branch_id=branch_inventory.branch_id
        and bm.user_id=auth.uid() and bm.is_active=true
    )
  )
)
with check (
  public.has_business_role(business_id,array['owner','admin','manager']::public.business_role[])
  or (
    public.has_business_role(business_id,array['storekeeper']::public.business_role[])
    and exists(
      select 1 from public.branch_members bm
      where bm.business_id=branch_inventory.business_id
        and bm.branch_id=branch_inventory.branch_id
        and bm.user_id=auth.uid() and bm.is_active=true
    )
  )
);

-- Replace the legacy product sync path so opening stock is assigned to an
-- explicitly selected branch instead of silently going to the first branch.
create or replace function public.sync_local_records(
  p_business_id uuid,
  p_event_id text,
  p_record_type text,
  p_records jsonb
) returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  r jsonb;
  v_branch uuid;
  v_role public.business_role;
  v_count integer := 0;
  v_key text;
begin
  if auth.uid() is null then raise exception 'Authentication required'; end if;
  select bm.role into v_role from public.business_members bm
  where bm.business_id=p_business_id and bm.user_id=auth.uid() and bm.is_active=true;
  if not found or v_role is null then raise exception 'Active business membership required'; end if;
  if not public.has_business_role(p_business_id,array['owner','admin','manager','cashier','storekeeper','accountant']::public.business_role[]) then
    raise exception 'Active business membership and platform access required';
  end if;
  if v_role not in ('owner','admin','manager','cashier','storekeeper','accountant') then
    raise exception 'Not authorised to synchronise records';
  end if;
  if v_role='cashier' and p_record_type not in ('customers') then
    raise exception 'Cashiers may synchronise customer records only';
  end if;
  if v_role='storekeeper' and p_record_type not in ('products','suppliers') then
    raise exception 'Storekeepers may synchronise products and suppliers only';
  end if;
  if v_role='accountant' and p_record_type not in ('expenses') then
    raise exception 'Accountants may synchronise expense records only';
  end if;
  if coalesce(trim(p_event_id),'')='' then raise exception 'Sync event ID is required'; end if;
  if p_record_type not in ('products','customers','suppliers','expenses') then
    raise exception 'Unsupported sync record type';
  end if;
  if jsonb_typeof(p_records)<>'array' then raise exception 'Records must be a JSON array'; end if;
  if exists(select 1 from public.offline_sync_receipts r
    where r.business_id=p_business_id and r.event_id=p_event_id) then
    return jsonb_build_object('status','already_synced','processed',0);
  end if;

  for r in select value from jsonb_array_elements(p_records) loop
    v_key := nullif(r->>'client_record_id','');
    if v_key is null then raise exception 'Every record needs a stable client_record_id'; end if;

    if p_record_type='products' then
      v_branch := nullif(r->>'branch_id','')::uuid;
      if v_branch is null or not exists(
        select 1 from public.branches b
        where b.id=v_branch and b.business_id=p_business_id and b.is_active=true
      ) then raise exception 'Choose an active branch for product opening stock'; end if;
      if v_role in ('cashier','storekeeper') and not exists(
        select 1 from public.branch_members bm
        where bm.business_id=p_business_id and bm.branch_id=v_branch
          and bm.user_id=auth.uid() and bm.is_active=true
      ) then raise exception 'You are not assigned to the selected branch'; end if;

      insert into public.products(
        business_id,client_record_id,sku,name,category,unit,cost_price,
        selling_price,reorder_level,is_active
      ) values(
        p_business_id,v_key,nullif(r->>'sku',''),
        coalesce(nullif(r->>'name',''),'Unnamed product'),
        nullif(r->>'category',''),coalesce(nullif(r->>'unit',''),'unit'),
        greatest(coalesce((r->>'cost_price')::numeric,0),0),
        greatest(coalesce((r->>'selling_price')::numeric,0),0),
        greatest(coalesce((r->>'reorder_level')::numeric,0),0),true
      )
      on conflict(business_id,client_record_id) where client_record_id is not null
      do update set sku=excluded.sku,name=excluded.name,category=excluded.category,
        unit=excluded.unit,cost_price=excluded.cost_price,
        selling_price=excluded.selling_price,reorder_level=excluded.reorder_level,
        updated_at=now();

      insert into public.branch_inventory(business_id,branch_id,product_id,quantity_on_hand)
      select p_business_id,v_branch,p.id,
        greatest(coalesce((r->>'quantity_on_hand')::numeric,0),0)
      from public.products p
      where p.business_id=p_business_id and p.client_record_id=v_key
      on conflict(branch_id,product_id) do update
        set quantity_on_hand=excluded.quantity_on_hand,updated_at=now();

    elsif p_record_type='customers' then
      insert into public.customers(business_id,client_record_id,name,phone,email,address,notes)
      values(p_business_id,v_key,coalesce(nullif(r->>'name',''),'Unnamed customer'),
        nullif(r->>'phone',''),nullif(r->>'email',''),nullif(r->>'address',''),nullif(r->>'notes',''))
      on conflict(business_id,client_record_id) where client_record_id is not null
      do update set name=excluded.name,phone=excluded.phone,email=excluded.email,
        address=excluded.address,notes=excluded.notes,updated_at=now();

    elsif p_record_type='suppliers' then
      insert into public.suppliers(business_id,client_record_id,name,phone,email,address,notes)
      values(p_business_id,v_key,coalesce(nullif(r->>'name',''),'Unnamed supplier'),
        nullif(r->>'phone',''),nullif(r->>'email',''),nullif(r->>'address',''),nullif(r->>'notes',''))
      on conflict(business_id,client_record_id) where client_record_id is not null
      do update set name=excluded.name,phone=excluded.phone,email=excluded.email,
        address=excluded.address,notes=excluded.notes,updated_at=now();

    elsif p_record_type='expenses' then
      insert into public.expenses(business_id,client_record_id,category,description,amount,payment_method,expense_date)
      values(p_business_id,v_key,coalesce(nullif(r->>'category',''),'General'),
        coalesce(nullif(r->>'description',''),'Expense'),
        greatest(coalesce((r->>'amount')::numeric,0.01),0.01),
        coalesce(nullif(r->>'payment_method',''),'cash'),
        coalesce(nullif(r->>'expense_date','')::date,current_date))
      on conflict(business_id,client_record_id) where client_record_id is not null
      do update set category=excluded.category,description=excluded.description,
        amount=excluded.amount,payment_method=excluded.payment_method,
        expense_date=excluded.expense_date;
    end if;
    v_count := v_count+1;
  end loop;

  insert into public.offline_sync_receipts(business_id,event_id,record_type,record_count)
  values(p_business_id,p_event_id,p_record_type,v_count);
  return jsonb_build_object('status','synced','processed',v_count);
end;
$$;


-- Branch-scoped read access: managers and accountants have workspace visibility;
-- cashiers/storekeepers see only records for branches to which they are assigned.
drop policy if exists branch_inventory_member_read on public.branch_inventory;
create policy branch_inventory_member_read on public.branch_inventory
for select to authenticated using (
 public.has_business_role(business_id,array['owner','admin','manager','accountant']::public.business_role[])
 or (
   public.has_business_role(business_id,array['cashier','storekeeper']::public.business_role[])
   and exists(select 1 from public.branch_members bm
     where bm.business_id=branch_inventory.business_id
       and bm.branch_id=branch_inventory.branch_id
       and bm.user_id=auth.uid() and bm.is_active)
 )
);

drop policy if exists offline_sales_member_read on public.offline_sales;
drop policy if exists offline_sales_branch_read on public.offline_sales;
create policy offline_sales_branch_read on public.offline_sales
for select to authenticated using (
 public.has_business_role(business_id,array['owner','admin','manager','accountant']::public.business_role[])
 or (
   public.has_business_role(business_id,array['cashier']::public.business_role[])
   and branch_id is not null
   and exists(select 1 from public.branch_members bm where bm.business_id=offline_sales.business_id
     and bm.branch_id=offline_sales.branch_id and bm.user_id=auth.uid() and bm.is_active)
 )
);

drop policy if exists offline_purchases_member_read on public.offline_purchases;
drop policy if exists offline_purchases_branch_read on public.offline_purchases;
create policy offline_purchases_branch_read on public.offline_purchases
for select to authenticated using (
 public.has_business_role(business_id,array['owner','admin','manager','accountant']::public.business_role[])
 or (
   public.has_business_role(business_id,array['storekeeper']::public.business_role[])
   and branch_id is not null
   and exists(select 1 from public.branch_members bm where bm.business_id=offline_purchases.business_id
     and bm.branch_id=offline_purchases.branch_id and bm.user_id=auth.uid() and bm.is_active)
 )
);

drop policy if exists offline_sale_items_member_read on public.offline_sale_items;
drop policy if exists offline_sale_items_branch_read on public.offline_sale_items;
create policy offline_sale_items_branch_read on public.offline_sale_items
for select to authenticated using (
 exists(select 1 from public.offline_sales s where s.id=offline_sale_items.sale_id and s.business_id=offline_sale_items.business_id)
);
drop policy if exists offline_purchase_items_member_read on public.offline_purchase_items;
drop policy if exists offline_purchase_items_branch_read on public.offline_purchase_items;
create policy offline_purchase_items_branch_read on public.offline_purchase_items
for select to authenticated using (
 exists(select 1 from public.offline_purchases p where p.id=offline_purchase_items.purchase_id and p.business_id=offline_purchase_items.business_id)
);

drop policy if exists branch_stock_transfers_member_read on public.branch_stock_transfers;
drop policy if exists branch_stock_transfers_branch_read on public.branch_stock_transfers;
create policy branch_stock_transfers_branch_read on public.branch_stock_transfers
for select to authenticated using (
 public.has_business_role(business_id,array['owner','admin','manager','accountant']::public.business_role[])
 or (
   public.has_business_role(business_id,array['storekeeper']::public.business_role[])
   and exists(select 1 from public.branch_members bm where bm.business_id=branch_stock_transfers.business_id
     and bm.branch_id in (branch_stock_transfers.source_branch_id,branch_stock_transfers.destination_branch_id)
     and bm.user_id=auth.uid() and bm.is_active
     group by bm.user_id having count(distinct bm.branch_id)=2)
 )
);
drop policy if exists branch_stock_transfer_items_member_read on public.branch_stock_transfer_items;
drop policy if exists branch_stock_transfer_items_branch_read on public.branch_stock_transfer_items;
create policy branch_stock_transfer_items_branch_read on public.branch_stock_transfer_items
for select to authenticated using (
 exists(select 1 from public.branch_stock_transfers t
   where t.id=branch_stock_transfer_items.transfer_id and t.business_id=branch_stock_transfer_items.business_id)
);

-- New branch-aware transaction RPC.
-- Managers/owners/admins may post to any active branch.
-- Cashiers may post sales only at assigned branches.
-- Storekeepers may post purchases only at assigned branches.
-- Accountants and viewers cannot post inventory transactions.
create or replace function public.sync_branch_transaction(
  p_business_id uuid,
  p_branch_id uuid,
  p_event_id text,
  p_transaction_type text,
  p_transaction jsonb
) returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_role public.business_role;
  v_sale uuid;
  v_purchase uuid;
  v_item jsonb;
  v_product uuid;
  v_qty numeric;
  v_price numeric;
  v_total numeric := 0;
  v_header_total numeric;
  v_count integer := 0;
  v_client_transaction_id text;
  v_receipt text;
  v_group record;
begin
  if auth.uid() is null then raise exception 'Authentication required'; end if;
  if coalesce(trim(p_event_id),'') = '' then raise exception 'Transaction event ID is required'; end if;
  if p_transaction_type not in ('sales','purchases') then raise exception 'Unsupported transaction type'; end if;
  if jsonb_typeof(p_transaction->'items') <> 'array'
     or jsonb_array_length(p_transaction->'items') = 0 then
    raise exception 'Transaction must contain at least one item';
  end if;

  select bm.role into v_role
  from public.business_members bm
  where bm.business_id = p_business_id
    and bm.user_id = auth.uid()
    and bm.is_active = true;
  if not found or v_role is null then raise exception 'Active business membership required'; end if;
  if not public.has_business_role(p_business_id,array['owner','admin','manager','cashier','storekeeper']::public.business_role[]) then
    raise exception 'Active business membership and platform access required';
  end if;

  if v_role not in ('owner','admin','manager','cashier','storekeeper') then
    raise exception 'Your role cannot post sales or purchases';
  end if;
  if v_role = 'cashier' and p_transaction_type <> 'sales' then
    raise exception 'Cashiers may post sales only';
  end if;
  if v_role = 'storekeeper' and p_transaction_type <> 'purchases' then
    raise exception 'Storekeepers may post purchases only';
  end if;

  if not exists (
    select 1 from public.branches b
    where b.id = p_branch_id and b.business_id = p_business_id and b.is_active = true
  ) then raise exception 'Select an active branch belonging to this business'; end if;

  if v_role in ('cashier','storekeeper') and not exists (
    select 1 from public.branch_members bm
    where bm.business_id = p_business_id
      and bm.branch_id = p_branch_id
      and bm.user_id = auth.uid()
      and bm.is_active = true
  ) then raise exception 'You are not assigned to the selected branch'; end if;

  if exists (
    select 1 from public.offline_sync_receipts r
    where r.business_id = p_business_id and r.event_id = p_event_id
  ) then
    return jsonb_build_object('status','already_synced','processed',0);
  end if;

  v_client_transaction_id := nullif(trim(p_transaction->>'client_transaction_id'),'');
  if v_client_transaction_id is null then raise exception 'Client transaction ID is required'; end if;
  v_header_total := (p_transaction->>'total')::numeric;
  if v_header_total is null or v_header_total < 0 then raise exception 'Transaction total must be zero or greater'; end if;

  -- Validate every line and calculate the authoritative rounded total before writes.
  for v_item in select value from jsonb_array_elements(p_transaction->'items') loop
    select p.id into v_product
    from public.products p
    where p.business_id = p_business_id
      and p.client_record_id = v_item->>'product_client_record_id'
      and p.is_active = true;
    if v_product is null then raise exception 'A product is missing, inactive, or not synced to this workspace'; end if;

    v_qty := (v_item->>'quantity')::numeric;
    if v_qty is null or v_qty <= 0 then raise exception 'Every transaction quantity must be greater than zero'; end if;

    if p_transaction_type = 'sales' then
      v_price := (v_item->>'unit_price')::numeric;
    else
      v_price := (v_item->>'unit_cost')::numeric;
    end if;
    if v_price is null or v_price < 0 then raise exception 'Every transaction unit price must be zero or greater'; end if;

    v_total := v_total + round(v_qty * v_price, 2);
    v_count := v_count + 1;
  end loop;

  if abs(v_total - v_header_total) > 0.01 then
    raise exception 'Transaction total does not match its item totals (calculated %, supplied %)', v_total, v_header_total;
  end if;

  -- Aggregate repeated product lines before checking/decrementing stock, preventing overselling.
  if p_transaction_type = 'sales' then
    for v_group in
      select p.id as product_id, sum((j.value->>'quantity')::numeric) as quantity,
             min(coalesce(nullif(j.value->>'product_name',''),p.name)) as product_name
      from jsonb_array_elements(p_transaction->'items') j(value)
      join public.products p
        on p.business_id = p_business_id
       and p.client_record_id = j.value->>'product_client_record_id'
       and p.is_active = true
      where coalesce((j.value->>'apply_stock')::boolean,true) = true
      group by p.id
      order by p.id
    loop
      update public.branch_inventory bi
      set quantity_on_hand = bi.quantity_on_hand - v_group.quantity,
          updated_at = now()
      where bi.business_id = p_business_id
        and bi.branch_id = p_branch_id
        and bi.product_id = v_group.product_id
        and bi.quantity_on_hand >= v_group.quantity;
      if not found then
        raise exception 'Insufficient stock at the selected branch for product %', v_group.product_name;
      end if;
      -- Keep tracked batch quantities aligned with POS stock consumption.
      perform public.consume_product_batches(
        p_business_id,p_branch_id,v_group.product_id,v_group.quantity
      );
    end loop;

    v_receipt := coalesce(nullif(p_transaction->>'receipt',''), 'WL-' || substr(p_event_id,1,12));
    insert into public.offline_sales(
      business_id,branch_id,client_transaction_id,receipt,transaction_date,
      customer_name,payment_method,total
    ) values (
      p_business_id,p_branch_id,v_client_transaction_id,v_receipt,
      coalesce(nullif(p_transaction->>'transaction_date','')::date,current_date),
      nullif(p_transaction->>'customer_name',''),
      coalesce(nullif(p_transaction->>'payment_method',''),'cash'),
      v_total
    ) returning id into v_sale;

    for v_item in select value from jsonb_array_elements(p_transaction->'items') loop
      select p.id into v_product
      from public.products p
      where p.business_id = p_business_id
        and p.client_record_id = v_item->>'product_client_record_id'
        and p.is_active = true;
      v_qty := (v_item->>'quantity')::numeric;
      v_price := (v_item->>'unit_price')::numeric;
      insert into public.offline_sale_items(
        business_id,sale_id,product_id,product_name,quantity,unit_price,line_total
      ) values (
        p_business_id,v_sale,v_product,
        coalesce(nullif(v_item->>'product_name',''),'Product'),
        v_qty,v_price,round(v_qty*v_price,2)
      );
    end loop;
  else
    -- Purchases add stock at the selected branch. Repeated lines are safely additive.
    insert into public.offline_purchases(
      business_id,branch_id,client_transaction_id,transaction_date,supplier_name,total
    ) values (
      p_business_id,p_branch_id,v_client_transaction_id,
      coalesce(nullif(p_transaction->>'transaction_date','')::date,current_date),
      nullif(p_transaction->>'supplier_name',''),v_total
    ) returning id into v_purchase;

    for v_item in select value from jsonb_array_elements(p_transaction->'items') loop
      select p.id into v_product
      from public.products p
      where p.business_id = p_business_id
        and p.client_record_id = v_item->>'product_client_record_id'
        and p.is_active = true;
      v_qty := (v_item->>'quantity')::numeric;
      v_price := (v_item->>'unit_cost')::numeric;

      if coalesce((v_item->>'apply_stock')::boolean,true) then
        insert into public.branch_inventory(business_id,branch_id,product_id,quantity_on_hand)
        values(p_business_id,p_branch_id,v_product,v_qty)
        on conflict(branch_id,product_id) do update
          set quantity_on_hand = public.branch_inventory.quantity_on_hand + excluded.quantity_on_hand,
              updated_at = now();
      end if;

      insert into public.offline_purchase_items(
        business_id,purchase_id,product_id,product_name,quantity,unit_cost,line_total
      ) values (
        p_business_id,v_purchase,v_product,
        coalesce(nullif(v_item->>'product_name',''),'Product'),
        v_qty,v_price,round(v_qty*v_price,2)
      );
    end loop;
  end if;

  insert into public.offline_sync_receipts(business_id,event_id,record_type,record_count)
  values(p_business_id,p_event_id,p_transaction_type,v_count);

  insert into public.audit_logs(business_id,actor_user_id,action,entity_table,entity_id,details)
  values(
    p_business_id,auth.uid(),'branch_' || p_transaction_type || '_posted',
    case when p_transaction_type='sales' then 'offline_sales' else 'offline_purchases' end,
    coalesce(v_sale,v_purchase)::text,
    jsonb_build_object('branch_id',p_branch_id,'item_count',v_count,'total',v_total)
  );

  return jsonb_build_object(
    'status','synced','processed',v_count,
    'transaction_id',coalesce(v_sale,v_purchase),'branch_id',p_branch_id,'total',v_total
  );
end;
$$;

revoke all on function public.sync_branch_transaction(uuid,uuid,text,text,jsonb) from public;
grant execute on function public.sync_branch_transaction(uuid,uuid,text,text,jsonb) to authenticated;

-- Prevent use of the old auto-first-branch RPC by normal authenticated clients.
-- The new client must call sync_branch_transaction with an explicit branch.
revoke all on function public.sync_local_transaction(uuid,text,text,jsonb) from authenticated;

-- Preserve batch/expiry traceability when a stock transfer is approved.
-- Helper function is installed by migration 011 in the same installer.
create or replace function public.approve_branch_stock_transfer(
  p_transfer_id uuid
) returns jsonb
language plpgsql security definer
set search_path = ''
as $$
declare
  v_transfer public.branch_stock_transfers%rowtype;
  v_item record;
  v_unbatched numeric;
begin
  if auth.uid() is null then raise exception 'Authentication required'; end if;
  select * into v_transfer from public.branch_stock_transfers
   where id=p_transfer_id for update;
  if not found then raise exception 'Transfer request not found'; end if;
  if v_transfer.status<>'pending' then raise exception 'Only pending transfers can be approved'; end if;
  if not public.has_business_role(v_transfer.business_id,
    array['owner','admin','manager']::public.business_role[]) then
    raise exception 'Only an owner, admin, or manager can approve a transfer';
  end if;

  for v_item in
    select product_id, sum(quantity)::numeric as quantity, min(product_name) as product_name
    from public.branch_stock_transfer_items
    where transfer_id=p_transfer_id and business_id=v_transfer.business_id
    group by product_id order by product_id
  loop
    perform 1 from public.branch_inventory
     where business_id=v_transfer.business_id
       and branch_id=v_transfer.source_branch_id
       and product_id=v_item.product_id
     for update;
    update public.branch_inventory
      set quantity_on_hand=quantity_on_hand-v_item.quantity,updated_at=now()
      where business_id=v_transfer.business_id
        and branch_id=v_transfer.source_branch_id
        and product_id=v_item.product_id
        and quantity_on_hand>=v_item.quantity;
    if not found then
      raise exception 'Insufficient source-branch stock for product %',v_item.product_name;
    end if;

    v_unbatched:=public.transfer_product_batches(
      v_transfer.business_id,v_transfer.source_branch_id,
      v_transfer.destination_branch_id,v_item.product_id,v_item.quantity
    );

    insert into public.branch_inventory(business_id,branch_id,product_id,quantity_on_hand,updated_at)
    values(v_transfer.business_id,v_transfer.destination_branch_id,v_item.product_id,v_item.quantity,now())
    on conflict(branch_id,product_id) do update
      set quantity_on_hand=public.branch_inventory.quantity_on_hand+excluded.quantity_on_hand,
          updated_at=now();
  end loop;

  update public.branch_stock_transfers
    set status='completed',approved_by=auth.uid(),completed_at=now()
    where id=p_transfer_id;

  insert into public.audit_logs(business_id,actor_user_id,action,entity_table,entity_id,details)
  values(v_transfer.business_id,auth.uid(),'branch_stock_transfer_approved',
    'branch_stock_transfers',p_transfer_id::text,
    jsonb_build_object('source_branch_id',v_transfer.source_branch_id,
      'destination_branch_id',v_transfer.destination_branch_id,
      'batch_traceability','FIFO batch quantities moved where available'));

  return jsonb_build_object('status','completed','transfer_id',p_transfer_id);
end;
$$;

revoke all on function public.approve_branch_stock_transfer(uuid) from public;
grant execute on function public.approve_branch_stock_transfer(uuid) to authenticated;

-- Only managers can reject a pending transfer; the reason is preserved for audit.
create or replace function public.reject_branch_stock_transfer(
  p_transfer_id uuid,
  p_reason text
) returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_transfer public.branch_stock_transfers%rowtype;
begin
  if auth.uid() is null then raise exception 'Authentication required'; end if;
  if coalesce(length(trim(p_reason)),0) < 3 then
    raise exception 'Enter a rejection reason of at least three characters';
  end if;

  select * into v_transfer
  from public.branch_stock_transfers
  where id = p_transfer_id
  for update;
  if not found then raise exception 'Transfer request not found'; end if;
  if v_transfer.status <> 'pending' then raise exception 'Only pending transfers can be rejected'; end if;
  if not public.has_business_role(
    v_transfer.business_id,
    array['owner','admin','manager']::public.business_role[]
  ) then raise exception 'Only an owner, admin, or manager can reject a transfer'; end if;

  update public.branch_stock_transfers
  set status='rejected', rejected_by=auth.uid(), rejected_at=now(), decision_note=trim(p_reason)
  where id=p_transfer_id;

  insert into public.audit_logs(business_id,actor_user_id,action,entity_table,entity_id,details)
  values(
    v_transfer.business_id,auth.uid(),'branch_stock_transfer_rejected',
    'branch_stock_transfers',p_transfer_id::text,
    jsonb_build_object('reason',trim(p_reason))
  );

  return jsonb_build_object('status','rejected','transfer_id',p_transfer_id);
end;
$$;

revoke all on function public.reject_branch_stock_transfer(uuid,text) from public;
grant execute on function public.reject_branch_stock_transfer(uuid,text) to authenticated;

-- MIGRATION 011: FINANCE AND INVENTORY CONTROLS
-- White Lion SME Business OS — Migration 011
-- Financial registers, product batches/expiry and controlled stock adjustments.

create table if not exists public.cashbook_entries (
  id uuid primary key default gen_random_uuid(),
  business_id uuid not null references public.businesses(id) on delete cascade,
  branch_id uuid null,
  entry_type text not null check (entry_type in ('income','expense')),
  category text not null,
  description text not null,
  amount numeric(14,2) not null check (amount > 0),
  payment_method text not null default 'cash',
  entry_date date not null default current_date,
  reference text null,
  created_by uuid null default auth.uid() references auth.users(id) on delete set null,
  created_at timestamptz not null default now(),
  constraint cashbook_branch_business_fk foreign key(branch_id,business_id)
    references public.branches(id,business_id) on delete set null (branch_id)
);

create table if not exists public.financial_obligations (
  id uuid primary key default gen_random_uuid(),
  business_id uuid not null references public.businesses(id) on delete cascade,
  branch_id uuid null,
  obligation_type text not null check (obligation_type in ('receivable','payable')),
  party_name text not null,
  description text not null,
  reference text null,
  amount numeric(14,2) not null check (amount > 0),
  amount_paid numeric(14,2) not null default 0 check (amount_paid >= 0 and amount_paid <= amount),
  due_date date null,
  status text not null default 'open' check (status in ('open','part_paid','settled','void')),
  created_by uuid null default auth.uid() references auth.users(id) on delete set null,
  created_at timestamptz not null default now(),
  constraint financial_obligations_branch_business_fk foreign key(branch_id,business_id)
    references public.branches(id,business_id) on delete set null (branch_id),
  constraint financial_obligations_id_business_uidx unique(id,business_id)
);

create table if not exists public.financial_obligation_payments (
  id uuid primary key default gen_random_uuid(),
  business_id uuid not null references public.businesses(id) on delete cascade,
  obligation_id uuid not null,
  amount numeric(14,2) not null check (amount > 0),
  payment_date date not null default current_date,
  payment_method text not null default 'cash',
  reference text null,
  created_by uuid null default auth.uid() references auth.users(id) on delete set null,
  created_at timestamptz not null default now(),
  constraint financial_payment_obligation_business_fk foreign key(obligation_id,business_id)
    references public.financial_obligations(id,business_id) on delete cascade
);
create index if not exists obligation_payments_obligation_idx
  on public.financial_obligation_payments(obligation_id,payment_date desc);
alter table public.financial_obligation_payments enable row level security;
drop policy if exists obligation_payments_member_read on public.financial_obligation_payments;
create policy obligation_payments_member_read on public.financial_obligation_payments
for select to authenticated using(public.is_business_member(business_id));
drop policy if exists obligation_payments_finance_write on public.financial_obligation_payments;
create policy obligation_payments_finance_write on public.financial_obligation_payments
for insert to authenticated with check(
 public.has_business_role(business_id,array['owner','admin','manager','accountant']::public.business_role[])
);

create table if not exists public.product_batches (
  id uuid primary key default gen_random_uuid(),
  business_id uuid not null references public.businesses(id) on delete cascade,
  branch_id uuid not null,
  product_id uuid not null,
  batch_number text not null,
  expiry_date date null,
  quantity_on_hand numeric(14,3) not null default 0 check (quantity_on_hand >= 0),
  unit_cost numeric(14,2) not null default 0 check (unit_cost >= 0),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint product_batches_branch_fk foreign key(branch_id,business_id)
    references public.branches(id,business_id) on delete cascade,
  constraint product_batches_product_fk foreign key(product_id,business_id)
    references public.products(id,business_id) on delete cascade,
  constraint product_batches_unique unique(branch_id,product_id,batch_number)
);

create table if not exists public.stock_adjustments (
  id uuid primary key default gen_random_uuid(),
  business_id uuid not null references public.businesses(id) on delete cascade,
  branch_id uuid not null,
  product_id uuid not null,
  adjustment_type text not null check (adjustment_type in ('increase','decrease')),
  quantity numeric(14,3) not null check (quantity > 0),
  reason text not null,
  status text not null default 'pending' check (status in ('pending','approved','rejected','cancelled')),
  requested_by uuid null default auth.uid() references auth.users(id) on delete set null,
  approved_by uuid null references auth.users(id) on delete set null,
  decision_note text null,
  created_at timestamptz not null default now(),
  decided_at timestamptz null,
  constraint stock_adjustments_branch_fk foreign key(branch_id,business_id)
    references public.branches(id,business_id) on delete cascade,
  constraint stock_adjustments_product_fk foreign key(product_id,business_id)
    references public.products(id,business_id) on delete cascade
);

alter table public.products add column if not exists barcode text;
create unique index if not exists products_business_barcode_uidx
  on public.products(business_id,barcode) where barcode is not null and barcode<>'';

create index if not exists cashbook_business_date_idx on public.cashbook_entries(business_id,entry_date desc);
create index if not exists obligations_business_status_idx on public.financial_obligations(business_id,status,due_date);
create index if not exists product_batches_expiry_idx on public.product_batches(business_id,expiry_date);
create index if not exists stock_adjustments_branch_status_idx on public.stock_adjustments(business_id,branch_id,status);

alter table public.cashbook_entries enable row level security;
alter table public.financial_obligations enable row level security;
alter table public.product_batches enable row level security;
alter table public.stock_adjustments enable row level security;

drop policy if exists cashbook_member_read on public.cashbook_entries;
create policy cashbook_member_read on public.cashbook_entries for select to authenticated
using(public.is_business_member(business_id));
drop policy if exists cashbook_finance_write on public.cashbook_entries;
create policy cashbook_finance_write on public.cashbook_entries for all to authenticated
using(public.has_business_role(business_id,array['owner','admin','manager','accountant']::public.business_role[]))
with check(public.has_business_role(business_id,array['owner','admin','manager','accountant']::public.business_role[]));

drop policy if exists obligations_member_read on public.financial_obligations;
create policy obligations_member_read on public.financial_obligations for select to authenticated
using(public.is_business_member(business_id));
drop policy if exists obligations_finance_write on public.financial_obligations;
create policy obligations_finance_write on public.financial_obligations for all to authenticated
using(public.has_business_role(business_id,array['owner','admin','manager','accountant']::public.business_role[]))
with check(public.has_business_role(business_id,array['owner','admin','manager','accountant']::public.business_role[]));

drop policy if exists batches_member_read on public.product_batches;
create policy batches_member_read on public.product_batches for select to authenticated
using(public.is_business_member(business_id));
drop policy if exists batches_inventory_write on public.product_batches;
create policy batches_inventory_write on public.product_batches for all to authenticated
using(
 public.has_business_role(business_id,array['owner','admin','manager']::public.business_role[])
 or (public.has_business_role(business_id,array['storekeeper']::public.business_role[])
 and exists(select 1 from public.branch_members bm where bm.business_id=product_batches.business_id
 and bm.branch_id=product_batches.branch_id and bm.user_id=auth.uid() and bm.is_active))
)
with check(
 public.has_business_role(business_id,array['owner','admin','manager']::public.business_role[])
 or (public.has_business_role(business_id,array['storekeeper']::public.business_role[])
 and exists(select 1 from public.branch_members bm where bm.business_id=product_batches.business_id
 and bm.branch_id=product_batches.branch_id and bm.user_id=auth.uid() and bm.is_active))
);

drop policy if exists adjustments_member_read on public.stock_adjustments;
create policy adjustments_member_read on public.stock_adjustments for select to authenticated
using(public.is_business_member(business_id));
-- Requests are made through a SECURITY DEFINER RPC; clients cannot forge approval fields.

-- Financial registers are visible only to owner/admin/manager/accountant roles.
drop policy if exists cashbook_member_read on public.cashbook_entries;
create policy cashbook_finance_read on public.cashbook_entries for select to authenticated
using(public.has_business_role(business_id,array['owner','admin','manager','accountant']::public.business_role[]));
drop policy if exists obligations_member_read on public.financial_obligations;
create policy obligations_finance_read on public.financial_obligations for select to authenticated
using(public.has_business_role(business_id,array['owner','admin','manager','accountant']::public.business_role[]));
drop policy if exists obligation_payments_member_read on public.financial_obligation_payments;
drop policy if exists obligation_payments_finance_write on public.financial_obligation_payments;
create policy obligation_payments_finance_read on public.financial_obligation_payments for select to authenticated
using(public.has_business_role(business_id,array['owner','admin','manager','accountant']::public.business_role[]));

drop policy if exists batches_member_read on public.product_batches;
create policy batches_branch_read on public.product_batches for select to authenticated using (
 public.has_business_role(business_id,array['owner','admin','manager','accountant']::public.business_role[])
 or (
   public.has_business_role(business_id,array['cashier','storekeeper']::public.business_role[])
   and exists(select 1 from public.branch_members bm where bm.business_id=product_batches.business_id
     and bm.branch_id=product_batches.branch_id and bm.user_id=auth.uid() and bm.is_active)
 )
);
drop policy if exists adjustments_member_read on public.stock_adjustments;
create policy adjustments_branch_read on public.stock_adjustments for select to authenticated using (
 public.has_business_role(business_id,array['owner','admin','manager']::public.business_role[])
 or (
   public.has_business_role(business_id,array['storekeeper']::public.business_role[])
   and exists(select 1 from public.branch_members bm where bm.business_id=stock_adjustments.business_id
     and bm.branch_id=stock_adjustments.branch_id and bm.user_id=auth.uid() and bm.is_active)
 )
);

drop policy if exists adjustments_no_direct_write on public.stock_adjustments;
create policy adjustments_no_direct_write on public.stock_adjustments for all to authenticated
using(false) with check(false);

-- Batch movement helpers. They consume tracked lots in FEFO order and
-- preserve lot number, expiry date and unit cost when stock moves between branches.
-- Any returned remainder represents unbatched opening or legacy stock.
create or replace function public.consume_product_batches(
 p_business_id uuid,p_branch_id uuid,p_product_id uuid,p_quantity numeric
) returns numeric
language plpgsql security definer set search_path=''
as $$
declare v_remaining numeric:=p_quantity; v_batch record; v_take numeric;
begin
 if p_quantity is null or p_quantity<=0 then return 0; end if;
 for v_batch in
   select id,quantity_on_hand
   from public.product_batches
   where business_id=p_business_id and branch_id=p_branch_id
     and product_id=p_product_id and quantity_on_hand>0
   order by expiry_date asc nulls last,created_at asc,id
   for update
 loop
   exit when v_remaining<=0;
   v_take:=least(v_remaining,v_batch.quantity_on_hand);
   update public.product_batches set quantity_on_hand=quantity_on_hand-v_take,updated_at=now()
   where id=v_batch.id;
   v_remaining:=v_remaining-v_take;
 end loop;
 return greatest(v_remaining,0);
end;
$$;

create or replace function public.transfer_product_batches(
 p_business_id uuid,p_source_branch_id uuid,p_destination_branch_id uuid,
 p_product_id uuid,p_quantity numeric
) returns numeric
language plpgsql security definer set search_path=''
as $$
declare v_remaining numeric:=p_quantity; v_batch record; v_take numeric;
begin
 if p_quantity is null or p_quantity<=0 then return 0; end if;
 for v_batch in
   select id,batch_number,expiry_date,quantity_on_hand,unit_cost
   from public.product_batches
   where business_id=p_business_id and branch_id=p_source_branch_id
     and product_id=p_product_id and quantity_on_hand>0
   order by expiry_date asc nulls last,created_at asc,id
   for update
 loop
   exit when v_remaining<=0;
   v_take:=least(v_remaining,v_batch.quantity_on_hand);
   update public.product_batches set quantity_on_hand=quantity_on_hand-v_take,updated_at=now()
   where id=v_batch.id;
   insert into public.product_batches(
     business_id,branch_id,product_id,batch_number,expiry_date,quantity_on_hand,unit_cost
   ) values(
     p_business_id,p_destination_branch_id,p_product_id,v_batch.batch_number,
     v_batch.expiry_date,v_take,v_batch.unit_cost
   )
   on conflict(branch_id,product_id,batch_number) do update
     set quantity_on_hand=public.product_batches.quantity_on_hand+excluded.quantity_on_hand,
         expiry_date=excluded.expiry_date,unit_cost=excluded.unit_cost,updated_at=now();
   v_remaining:=v_remaining-v_take;
 end loop;
 return greatest(v_remaining,0);
end;
$$;

revoke all on function public.consume_product_batches(uuid,uuid,uuid,numeric) from public;
revoke all on function public.transfer_product_batches(uuid,uuid,uuid,uuid,numeric) from public;

create or replace function public.request_stock_adjustment(
 p_business_id uuid,p_branch_id uuid,p_product_id uuid,p_adjustment_type text,
 p_quantity numeric,p_reason text
) returns jsonb language plpgsql security definer set search_path=''
as $$
declare v_id uuid; v_role public.business_role;
begin
 if auth.uid() is null then raise exception 'Authentication required'; end if;
 select role into v_role from public.business_members
 where business_id=p_business_id and user_id=auth.uid() and is_active;
 if not public.has_business_role(p_business_id,array['owner','admin','manager','storekeeper']::public.business_role[]) then
   raise exception 'Not authorised to request stock adjustments';
 end if;
 if p_adjustment_type not in ('increase','decrease') or p_quantity is null or p_quantity<=0
   or length(trim(coalesce(p_reason,'')))<3 then raise exception 'Valid adjustment type, quantity and reason are required'; end if;
 if not exists(select 1 from public.branches where id=p_branch_id and business_id=p_business_id and is_active)
 then raise exception 'Active branch not found'; end if;
 if not exists(select 1 from public.products where id=p_product_id and business_id=p_business_id and is_active)
 then raise exception 'Active product not found'; end if;
 if v_role='storekeeper' and not exists(select 1 from public.branch_members
   where business_id=p_business_id and branch_id=p_branch_id and user_id=auth.uid() and is_active)
 then raise exception 'You are not assigned to this branch'; end if;
 insert into public.stock_adjustments(business_id,branch_id,product_id,adjustment_type,quantity,reason)
 values(p_business_id,p_branch_id,p_product_id,p_adjustment_type,p_quantity,trim(p_reason))
 returning id into v_id;
 insert into public.audit_logs(business_id,actor_user_id,action,entity_table,entity_id,details)
 values(p_business_id,auth.uid(),'stock_adjustment_requested','stock_adjustments',v_id::text,
 jsonb_build_object('branch_id',p_branch_id,'product_id',p_product_id,'type',p_adjustment_type,'quantity',p_quantity,'reason',trim(p_reason)));
 return jsonb_build_object('status','pending','adjustment_id',v_id);
end; $$;

create or replace function public.decide_stock_adjustment(
 p_adjustment_id uuid,p_approve boolean,p_note text default null
) returns jsonb language plpgsql security definer set search_path=''
as $$
declare v public.stock_adjustments%rowtype; v_role public.business_role; v_stock numeric;
begin
 if auth.uid() is null then raise exception 'Authentication required'; end if;
 select * into v from public.stock_adjustments where id=p_adjustment_id for update;
 if not found then raise exception 'Adjustment request not found'; end if;
 select role into v_role from public.business_members
 where business_id=v.business_id and user_id=auth.uid() and is_active;
 if not public.has_business_role(v.business_id,array['owner','admin','manager']::public.business_role[]) then
   raise exception 'Only owner, admin or manager can decide adjustments';
 end if;
 if v.status<>'pending' then raise exception 'Only pending adjustments can be decided'; end if;
 if p_approve then
   if v.adjustment_type='increase' then
     insert into public.branch_inventory(business_id,branch_id,product_id,quantity_on_hand)
     values(v.business_id,v.branch_id,v.product_id,v.quantity)
     on conflict(branch_id,product_id) do update set quantity_on_hand=public.branch_inventory.quantity_on_hand+excluded.quantity_on_hand,updated_at=now();
   else
     update public.branch_inventory set quantity_on_hand=quantity_on_hand-v.quantity,updated_at=now()
     where business_id=v.business_id and branch_id=v.branch_id and product_id=v.product_id
       and quantity_on_hand>=v.quantity;
     if not found then raise exception 'Insufficient stock for this adjustment'; end if;
     perform public.consume_product_batches(v.business_id,v.branch_id,v.product_id,v.quantity);
   end if;
 end if;
 update public.stock_adjustments set status=case when p_approve then 'approved' else 'rejected' end,
 approved_by=auth.uid(),decision_note=nullif(trim(coalesce(p_note,'')),''),decided_at=now()
 where id=p_adjustment_id;
 insert into public.audit_logs(business_id,actor_user_id,action,entity_table,entity_id,details)
 values(v.business_id,auth.uid(),case when p_approve then 'stock_adjustment_approved' else 'stock_adjustment_rejected' end,
 'stock_adjustments',p_adjustment_id::text,jsonb_build_object('note',p_note,'quantity',v.quantity,'type',v.adjustment_type));
 return jsonb_build_object('status',case when p_approve then 'approved' else 'rejected' end,'adjustment_id',p_adjustment_id);
end; $$;


create or replace function public.record_obligation_payment(
 p_obligation_id uuid,p_amount numeric,p_payment_method text default 'cash',
 p_payment_date date default current_date,p_reference text default null
) returns jsonb language plpgsql security definer set search_path=''
as $$
declare v public.financial_obligations%rowtype; v_role public.business_role; v_payment uuid; v_new_paid numeric; v_cash_type text;
begin
 if auth.uid() is null then raise exception 'Authentication required'; end if;
 select * into v from public.financial_obligations where id=p_obligation_id for update;
 if not found then raise exception 'Receivable or payable record not found'; end if;
 select role into v_role from public.business_members
 where business_id=v.business_id and user_id=auth.uid() and is_active;
 if not public.has_business_role(v.business_id,array['owner','admin','manager','accountant']::public.business_role[]) then
   raise exception 'Not authorised to record financial payments';
 end if;
 if v.status='void' then raise exception 'Voided receivables or payables cannot receive payments'; end if;
 if p_amount is null or p_amount<=0 or p_amount>v.amount-v.amount_paid then
   raise exception 'Payment must be positive and cannot exceed the outstanding balance';
 end if;
 v_new_paid:=v.amount_paid+p_amount;
 insert into public.financial_obligation_payments(business_id,obligation_id,amount,payment_date,payment_method,reference)
 values(v.business_id,v.id,p_amount,coalesce(p_payment_date,current_date),coalesce(nullif(p_payment_method,''),'cash'),nullif(trim(coalesce(p_reference,'')),''))
 returning id into v_payment;
 update public.financial_obligations set amount_paid=v_new_paid,
 status=case when v_new_paid>=amount then 'settled' else 'part_paid' end
 where id=v.id;
 v_cash_type:=case when v.obligation_type='receivable' then 'income' else 'expense' end;
 insert into public.cashbook_entries(business_id,branch_id,entry_type,category,description,amount,payment_method,entry_date,reference)
 values(v.business_id,v.branch_id,v_cash_type,
   case when v.obligation_type='receivable' then 'Receivable payment' else 'Payable payment' end,
   v.party_name||' · '||v.description,p_amount,coalesce(nullif(p_payment_method,''),'cash'),
   coalesce(p_payment_date,current_date),coalesce(nullif(trim(coalesce(p_reference,'')),''),'PAY-'||v_payment::text));
 insert into public.audit_logs(business_id,actor_user_id,action,entity_table,entity_id,details)
 values(v.business_id,auth.uid(),'financial_obligation_payment_recorded','financial_obligations',v.id::text,
 jsonb_build_object('payment_id',v_payment,'amount',p_amount,'amount_paid',v_new_paid,'status',case when v_new_paid>=v.amount then 'settled' else 'part_paid' end));
 return jsonb_build_object('status',case when v_new_paid>=v.amount then 'settled' else 'part_paid' end,'payment_id',v_payment,'amount_paid',v_new_paid);
end; $$;

create or replace function public.receive_product_batch(
 p_business_id uuid,p_branch_id uuid,p_product_id uuid,p_batch_number text,
 p_expiry_date date,p_quantity numeric,p_unit_cost numeric
) returns jsonb language plpgsql security definer set search_path=''
as $$
declare v_role public.business_role; v_batch uuid;
begin
 if auth.uid() is null then raise exception 'Authentication required'; end if;
 select role into v_role from public.business_members
 where business_id=p_business_id and user_id=auth.uid() and is_active;
 if not public.has_business_role(p_business_id,array['owner','admin','manager','storekeeper']::public.business_role[]) then
   raise exception 'Not authorised to receive stock batches';
 end if;
 if v_role='storekeeper' and not exists(select 1 from public.branch_members
   where business_id=p_business_id and branch_id=p_branch_id and user_id=auth.uid() and is_active)
 then raise exception 'You are not assigned to this branch'; end if;
 if length(trim(coalesce(p_batch_number,'')))<1 or p_quantity is null or p_quantity<=0
   or p_unit_cost is null or p_unit_cost<0 then raise exception 'Batch number, positive quantity and valid cost are required'; end if;
 if not exists(select 1 from public.branches where id=p_branch_id and business_id=p_business_id and is_active)
   or not exists(select 1 from public.products where id=p_product_id and business_id=p_business_id and is_active)
 then raise exception 'Active branch or product not found'; end if;
 insert into public.product_batches(business_id,branch_id,product_id,batch_number,expiry_date,quantity_on_hand,unit_cost)
 values(p_business_id,p_branch_id,p_product_id,trim(p_batch_number),p_expiry_date,p_quantity,p_unit_cost)
 on conflict(branch_id,product_id,batch_number) do update
 set expiry_date=excluded.expiry_date,quantity_on_hand=public.product_batches.quantity_on_hand+excluded.quantity_on_hand,
     unit_cost=excluded.unit_cost,updated_at=now()
 returning id into v_batch;
 insert into public.branch_inventory(business_id,branch_id,product_id,quantity_on_hand)
 values(p_business_id,p_branch_id,p_product_id,p_quantity)
 on conflict(branch_id,product_id) do update
 set quantity_on_hand=public.branch_inventory.quantity_on_hand+excluded.quantity_on_hand,updated_at=now();
 insert into public.audit_logs(business_id,actor_user_id,action,entity_table,entity_id,details)
 values(p_business_id,auth.uid(),'product_batch_received','product_batches',v_batch::text,
 jsonb_build_object('branch_id',p_branch_id,'product_id',p_product_id,'batch_number',p_batch_number,'quantity',p_quantity,'expiry_date',p_expiry_date));
 return jsonb_build_object('status','received','batch_id',v_batch);
end; $$;

-- Explicit authenticated table privileges; RLS above remains the row-level gate.
revoke all on public.cashbook_entries, public.financial_obligations,
  public.financial_obligation_payments, public.product_batches,
  public.stock_adjustments from anon, public, authenticated;
grant select, insert on public.cashbook_entries, public.financial_obligations to authenticated;
-- Payment rows are inserted only by the SECURITY DEFINER payment RPC, which
-- updates the obligation balance and cashbook in the same database transaction.
grant select on public.financial_obligation_payments, public.product_batches,
  public.stock_adjustments to authenticated;

revoke all on function public.record_obligation_payment(uuid,numeric,text,date,text) from public;
grant execute on function public.record_obligation_payment(uuid,numeric,text,date,text) to authenticated;
revoke all on function public.receive_product_batch(uuid,uuid,uuid,text,date,numeric,numeric) from public;
grant execute on function public.receive_product_batch(uuid,uuid,uuid,text,date,numeric,numeric) to authenticated;
revoke all on function public.request_stock_adjustment(uuid,uuid,uuid,text,numeric,text) from public;
revoke all on function public.decide_stock_adjustment(uuid,boolean,text) from public;
grant execute on function public.request_stock_adjustment(uuid,uuid,uuid,text,numeric,text) to authenticated;
grant execute on function public.decide_stock_adjustment(uuid,boolean,text) to authenticated;

commit;

-- POST-INSTALL VERIFICATION
-- Expected result: every row should show INSTALLED.
with checks(component, installed) as (
  values
    ('Branch membership table', to_regclass('public.branch_members') is not null),
    ('Branch stock transfer tables', to_regclass('public.branch_stock_transfers') is not null and to_regclass('public.branch_stock_transfer_items') is not null),
    ('Branch-aware transaction RPC', to_regprocedure('public.sync_branch_transaction(uuid,uuid,text,text,jsonb)') is not null),
    ('Legacy transaction RPC disabled for authenticated users', not has_function_privilege('authenticated', to_regprocedure('public.sync_local_transaction(uuid,text,text,jsonb)'), 'EXECUTE')),
    ('Transfer rejection RPC', to_regprocedure('public.reject_branch_stock_transfer(uuid,text)') is not null),
    ('Batch FEFO consumption helper', to_regprocedure('public.consume_product_batches(uuid,uuid,uuid,numeric)') is not null),
    ('Batch-preserving transfer helper', to_regprocedure('public.transfer_product_batches(uuid,uuid,uuid,uuid,numeric)') is not null),
    ('Cashbook table', to_regclass('public.cashbook_entries') is not null),
    ('Receivables/payables table', to_regclass('public.financial_obligations') is not null),
    ('Financial payment ledger', to_regclass('public.financial_obligation_payments') is not null),
    ('Same-business payment foreign key', exists(select 1 from pg_constraint where conname='financial_payment_obligation_business_fk')),
    ('Product batch and expiry table', to_regclass('public.product_batches') is not null),
    ('Stock adjustment table', to_regclass('public.stock_adjustments') is not null),
    ('Stock adjustment approval RPC', to_regprocedure('public.decide_stock_adjustment(uuid,boolean,text)') is not null),
    ('Financial payment RPC', to_regprocedure('public.record_obligation_payment(uuid,numeric,text,date,text)') is not null),
    ('Batch receiving RPC', to_regprocedure('public.receive_product_batch(uuid,uuid,uuid,text,date,numeric,numeric)') is not null),
    ('Barcode field', exists(select 1 from information_schema.columns where table_schema='public' and table_name='products' and column_name='barcode')),
    ('Branch-scoped inventory write policy', exists(select 1 from pg_policies where schemaname='public' and tablename='branch_inventory' and policyname='branch_inventory_manage')),
    ('Finance-only cashbook visibility', exists(select 1 from pg_policies where schemaname='public' and tablename='cashbook_entries' and policyname='cashbook_finance_read')),
    ('Payment table is read-only to authenticated clients', not has_table_privilege('authenticated','public.financial_obligation_payments','INSERT'))
)
select component, case when installed then 'INSTALLED' else 'MISSING' end as status
from checks
order by component;


-- ================================================================
-- MIGRATION 017: BANK AND MOBILE-MONEY STATEMENT RECONCILIATION
-- ================================================================
-- White Lion SME Business OS — Migration 017
-- Bank and mobile-money statement import and cashbook reconciliation.
-- CSV statements are imported by an authorised finance user; no bank API is implied.
begin;

create table if not exists public.bank_accounts (
  id uuid primary key default gen_random_uuid(),
  business_id uuid not null references public.businesses(id) on delete cascade,
  branch_id uuid,
  account_name text not null check (length(trim(account_name)) between 2 and 100),
  institution_name text not null check (length(trim(institution_name)) between 2 and 120),
  account_type text not null default 'bank' check (account_type in ('bank','mobile_money','cash_clearing','other')),
  account_last4 text check (account_last4 is null or account_last4 ~ '^[0-9]{4}$'),
  currency text not null default 'SLE' check (currency ~ '^[A-Z]{3}$'),
  opening_balance numeric(14,2) not null default 0,
  is_active boolean not null default true,
  created_by uuid default auth.uid() references auth.users(id) on delete set null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique(id,business_id),
  foreign key(branch_id,business_id) references public.branches(id,business_id) on delete set null (branch_id)
);

create unique index if not exists cashbook_entries_id_business_uidx
  on public.cashbook_entries(id,business_id);

alter table public.cashbook_entries
  add column if not exists bank_account_id uuid;
create index if not exists cashbook_bank_account_date_idx
  on public.cashbook_entries(business_id,bank_account_id,entry_date desc);

do $$
begin
  if not exists (select 1 from pg_constraint where conname='cashbook_bank_account_business_fk') then
    alter table public.cashbook_entries
      add constraint cashbook_bank_account_business_fk
      foreign key(bank_account_id,business_id)
      references public.bank_accounts(id,business_id) on delete restrict;
  end if;
end $$;

create table if not exists public.bank_statement_lines (
  id uuid primary key default gen_random_uuid(),
  business_id uuid not null,
  bank_account_id uuid not null,
  transaction_date date not null,
  description text not null check (length(trim(description)) between 1 and 500),
  reference text,
  amount numeric(14,2) not null check (amount > 0),
  direction text not null check (direction in ('debit','credit')),
  status text not null default 'unmatched' check (status in ('unmatched','matched','ignored')),
  matched_cashbook_entry_id uuid,
  matched_by uuid references auth.users(id) on delete set null,
  matched_at timestamptz,
  imported_by uuid default auth.uid() references auth.users(id) on delete set null,
  imported_at timestamptz not null default now(),
  foreign key(bank_account_id,business_id) references public.bank_accounts(id,business_id) on delete cascade,
  foreign key(matched_cashbook_entry_id,business_id) references public.cashbook_entries(id,business_id) on delete restrict,
  unique(id,business_id)
);

create unique index if not exists bank_statement_external_ref_uidx
  on public.bank_statement_lines(bank_account_id,reference)
  where reference is not null and reference <> '';
create unique index if not exists bank_statement_cashbook_match_uidx
  on public.bank_statement_lines(matched_cashbook_entry_id)
  where matched_cashbook_entry_id is not null;
create index if not exists bank_statement_reconcile_idx
  on public.bank_statement_lines(business_id,bank_account_id,transaction_date,status);
create index if not exists bank_accounts_business_idx
  on public.bank_accounts(business_id,is_active);

alter table public.bank_accounts enable row level security;
alter table public.bank_statement_lines enable row level security;

drop policy if exists bank_accounts_finance_read on public.bank_accounts;
create policy bank_accounts_finance_read on public.bank_accounts
for select to authenticated
using (public.has_business_role(business_id,array['owner','admin','manager','accountant']::public.business_role[]));

drop policy if exists bank_accounts_finance_manage on public.bank_accounts;
create policy bank_accounts_finance_manage on public.bank_accounts
for all to authenticated
using (public.has_business_role(business_id,array['owner','admin','accountant']::public.business_role[]))
with check (public.has_business_role(business_id,array['owner','admin','accountant']::public.business_role[]));

drop policy if exists bank_statement_finance_read on public.bank_statement_lines;
create policy bank_statement_finance_read on public.bank_statement_lines
for select to authenticated
using (public.has_business_role(business_id,array['owner','admin','manager','accountant']::public.business_role[]));

-- Statement lines are written only through the validated import/match RPCs.
drop policy if exists bank_statement_no_direct_write on public.bank_statement_lines;
create policy bank_statement_no_direct_write on public.bank_statement_lines
for all to authenticated using(false) with check(false);

revoke all on public.bank_accounts,public.bank_statement_lines from anon,public,authenticated;
grant select,insert,update,delete on public.bank_accounts to authenticated;
grant select on public.bank_statement_lines to authenticated;

create or replace function public.import_bank_statement_lines(
  p_bank_account_id uuid,
  p_lines jsonb
) returns jsonb
language plpgsql
security definer
set search_path=''
as $$
declare
  v_business_id uuid;
  v_count integer := 0;
begin
  if auth.uid() is null then raise exception 'Authentication required'; end if;
  select business_id into v_business_id
  from public.bank_accounts
  where id=p_bank_account_id and is_active
  for update;
  if not found then raise exception 'Active bank or mobile-money account not found'; end if;
  if not public.has_business_role(v_business_id,array['owner','admin','accountant']::public.business_role[]) then
    raise exception 'Only an owner, administrator or accountant can import statements';
  end if;
  if p_lines is null then raise exception 'Statement rows are required'; end if;
  if jsonb_typeof(p_lines)<>'array' then raise exception 'Statement rows must be a JSON array'; end if;
  if jsonb_array_length(p_lines)=0 or jsonb_array_length(p_lines)>5000 then
    raise exception 'Provide between 1 and 5000 statement rows';
  end if;
  if exists (
    select 1
    from jsonb_to_recordset(p_lines) as x(transaction_date date,description text,reference text,amount numeric,direction text)
    where x.transaction_date is null
       or length(trim(coalesce(x.description,'')))=0
       or x.amount is null or x.amount<=0
       or x.direction is null or x.direction not in ('debit','credit')
  ) then raise exception 'Every row needs a date, description, positive amount and debit/credit direction'; end if;

  insert into public.bank_statement_lines(
    business_id,bank_account_id,transaction_date,description,reference,amount,direction,imported_by
  )
  select v_business_id,p_bank_account_id,x.transaction_date,trim(x.description),
         nullif(trim(coalesce(x.reference,'')),''),x.amount,x.direction,auth.uid()
  from jsonb_to_recordset(p_lines) as x(
    transaction_date date,description text,reference text,amount numeric,direction text
  )
  on conflict (bank_account_id,reference)
    where reference is not null and reference<>''
    do nothing;
  get diagnostics v_count = row_count;
  insert into public.audit_logs(business_id,actor_user_id,action,entity_table,entity_id,details)
  values(v_business_id,auth.uid(),'bank_statement_imported','bank_statement_lines',p_bank_account_id::text,
    jsonb_build_object('bank_account_id',p_bank_account_id,'inserted_rows',v_count));
  return jsonb_build_object('status','imported','inserted_rows',v_count);
end;
$$;

create or replace function public.match_bank_statement_line(
  p_statement_line_id uuid,
  p_cashbook_entry_id uuid
) returns jsonb
language plpgsql
security definer
set search_path=''
as $$
declare
  v_line public.bank_statement_lines%rowtype;
  v_cash public.cashbook_entries%rowtype;
begin
  if auth.uid() is null then raise exception 'Authentication required'; end if;
  select * into v_line from public.bank_statement_lines
  where id=p_statement_line_id for update;
  if not found then raise exception 'Statement line not found'; end if;
  if not public.has_business_role(v_line.business_id,array['owner','admin','accountant']::public.business_role[]) then
    raise exception 'Only an owner, administrator or accountant can reconcile statements';
  end if;
  select * into v_cash from public.cashbook_entries
  where id=p_cashbook_entry_id and business_id=v_line.business_id for update;
  if not found then raise exception 'Matching cashbook entry not found in this business'; end if;
  if v_line.status<>'unmatched' then raise exception 'This statement line is not unmatched'; end if;
  if v_cash.bank_account_id is distinct from v_line.bank_account_id then
    raise exception 'The cashbook entry must belong to the same bank or mobile-money account';
  end if;
  if abs(v_cash.amount-v_line.amount)>0.01 then
    raise exception 'Amounts do not match; review the entries before reconciling';
  end if;
  if (v_line.direction='credit' and v_cash.entry_type<>'income')
     or (v_line.direction='debit' and v_cash.entry_type<>'expense') then
    raise exception 'Statement direction does not match the cashbook entry';
  end if;
  update public.bank_statement_lines
  set status='matched',matched_cashbook_entry_id=v_cash.id,matched_by=auth.uid(),matched_at=now()
  where id=v_line.id;
  insert into public.audit_logs(business_id,actor_user_id,action,entity_table,entity_id,details)
  values(v_line.business_id,auth.uid(),'bank_statement_line_matched','bank_statement_lines',v_line.id::text,
    jsonb_build_object('cashbook_entry_id',v_cash.id,'bank_account_id',v_line.bank_account_id,'amount',v_line.amount));
  return jsonb_build_object('status','matched','statement_line_id',v_line.id,'cashbook_entry_id',v_cash.id);
end;
$$;

revoke all on function public.import_bank_statement_lines(uuid,jsonb) from public;
revoke all on function public.match_bank_statement_line(uuid,uuid) from public;
grant execute on function public.import_bank_statement_lines(uuid,jsonb) to authenticated;
grant execute on function public.match_bank_statement_line(uuid,uuid) to authenticated;

commit;




-- ============================================================
-- MIGRATION 018: DOUBLE-ENTRY GENERAL LEDGER
-- Kept in sync with supabase/migrations/018_double_entry_general_ledger.sql
-- ============================================================

-- White Lion SME Business OS — Migration 018
-- Double-entry general ledger, automated source posting and financial reports.
-- Existing operational records are preserved. Triggers post new source records only.
begin;

create table if not exists public.chart_of_accounts (
  id uuid primary key default gen_random_uuid(),
  business_id uuid not null references public.businesses(id) on delete cascade,
  account_code text not null check (account_code ~ '^[0-9]{4,6}$'),
  account_name text not null check (length(trim(account_name)) between 2 and 120),
  account_type text not null check (account_type in ('asset','liability','equity','income','expense')),
  normal_balance text not null check (normal_balance in ('debit','credit')),
  is_system boolean not null default false,
  is_active boolean not null default true,
  created_at timestamptz not null default now(),
  unique (business_id,account_code),
  unique (id,business_id)
);

create table if not exists public.journal_entries (
  id uuid primary key default gen_random_uuid(),
  business_id uuid not null references public.businesses(id) on delete cascade,
  entry_number bigint generated always as identity,
  journal_date date not null default current_date,
  memo text not null check (length(trim(memo)) between 2 and 500),
  source_type text not null default 'manual',
  source_id text,
  status text not null default 'draft' check (status in ('draft','posted')),
  created_by uuid references auth.users(id) on delete set null default auth.uid(),
  posted_by uuid references auth.users(id) on delete set null,
  posted_at timestamptz,
  created_at timestamptz not null default now(),
  unique (id,business_id),
  unique (business_id,source_type,source_id),
  check ((status='draft' and posted_at is null) or (status='posted' and posted_at is not null))
);

create table if not exists public.journal_lines (
  id uuid primary key default gen_random_uuid(),
  business_id uuid not null,
  journal_entry_id uuid not null,
  account_id uuid not null,
  description text,
  debit numeric(18,2) not null default 0 check (debit >= 0),
  credit numeric(18,2) not null default 0 check (credit >= 0),
  created_at timestamptz not null default now(),
  foreign key (journal_entry_id,business_id)
    references public.journal_entries(id,business_id) on delete restrict,
  foreign key (account_id,business_id)
    references public.chart_of_accounts(id,business_id) on delete restrict,
  check ((debit > 0 and credit = 0) or (credit > 0 and debit = 0))
);

create index if not exists chart_accounts_business_type_idx
  on public.chart_of_accounts(business_id,account_type,account_code);
create index if not exists journal_entries_business_date_idx
  on public.journal_entries(business_id,journal_date desc,status);
create index if not exists journal_lines_business_account_idx
  on public.journal_lines(business_id,account_id,journal_entry_id);

alter table public.chart_of_accounts enable row level security;
alter table public.journal_entries enable row level security;
alter table public.journal_lines enable row level security;

drop policy if exists chart_accounts_member_read on public.chart_of_accounts;
create policy chart_accounts_member_read on public.chart_of_accounts
for select to authenticated using (public.is_business_member(business_id));
drop policy if exists journal_entries_finance_read on public.journal_entries;
create policy journal_entries_finance_read on public.journal_entries
for select to authenticated using (
  public.has_business_role(business_id,array['owner','admin','manager','accountant']::public.business_role[])
);
drop policy if exists journal_lines_finance_read on public.journal_lines;
create policy journal_lines_finance_read on public.journal_lines
for select to authenticated using (
  public.has_business_role(business_id,array['owner','admin','manager','accountant']::public.business_role[])
);

revoke all on public.chart_of_accounts,public.journal_entries,public.journal_lines from anon,public,authenticated;
grant select on public.chart_of_accounts,public.journal_entries,public.journal_lines to authenticated;

create or replace function public.seed_default_chart_of_accounts(p_business_id uuid)
returns void language plpgsql security definer set search_path=''
as $$
begin
  insert into public.chart_of_accounts(business_id,account_code,account_name,account_type,normal_balance,is_system)
  values
    (p_business_id,'1000','Cash and bank','asset','debit',true),
    (p_business_id,'1100','Accounts receivable','asset','debit',true),
    (p_business_id,'1200','Inventory','asset','debit',true),
    (p_business_id,'1500','Property and equipment','asset','debit',true),
    (p_business_id,'2000','Accounts payable','liability','credit',true),
    (p_business_id,'2100','Other liabilities','liability','credit',true),
    (p_business_id,'3000','Owner capital','equity','credit',true),
    (p_business_id,'3200','Retained earnings','equity','credit',true),
    (p_business_id,'4000','Sales revenue','income','credit',true),
    (p_business_id,'4050','Sales returns and allowances','income','debit',true),
    (p_business_id,'4100','Other operating income','income','credit',true),
    (p_business_id,'5000','Cost of goods sold','expense','debit',true),
    (p_business_id,'6000','Operating expenses','expense','debit',true),
    (p_business_id,'6100','Bank and payment charges','expense','debit',true)
  on conflict (business_id,account_code) do nothing;
end;
$$;

create or replace function public.accounting_business_created()
returns trigger language plpgsql security definer set search_path=''
as $$
begin
  perform public.seed_default_chart_of_accounts(new.id);
  return new;
end;
$$;
drop trigger if exists trg_accounting_seed_business on public.businesses;
create trigger trg_accounting_seed_business after insert on public.businesses
for each row execute function public.accounting_business_created();

-- Seed charts for businesses that existed before this migration.
do $$
declare r record;
begin
  for r in select id from public.businesses loop
    perform public.seed_default_chart_of_accounts(r.id);
  end loop;
end;
$$;

create or replace function public.initialize_accounting(p_business_id uuid)
returns jsonb language plpgsql security definer set search_path=''
as $$
begin
  if auth.uid() is null or not public.has_business_role(
    p_business_id,array['owner','admin','accountant']::public.business_role[]
  ) then raise exception 'Only an owner, administrator or accountant can initialise accounting'; end if;
  perform public.seed_default_chart_of_accounts(p_business_id);
  return jsonb_build_object('status','ready','account_count',
    (select count(*) from public.chart_of_accounts where business_id=p_business_id));
end;
$$;

-- Internal posting routine. The source record and journal are committed atomically.
create or replace function public.post_system_journal(
  p_business_id uuid,p_journal_date date,p_memo text,p_source_type text,p_source_id text,p_lines jsonb
) returns uuid language plpgsql security definer set search_path=''
as $$
declare
  v_journal_id uuid;
  v_debits numeric(18,2);
  v_credits numeric(18,2);
  v_count integer;
  v_missing integer;
begin
  perform public.seed_default_chart_of_accounts(p_business_id);
  if jsonb_typeof(p_lines)<>'array' or jsonb_array_length(p_lines)<2 then
    raise exception 'A journal must contain at least two lines';
  end if;
  select count(*),coalesce(sum(x.debit),0),coalesce(sum(x.credit),0)
  into v_count,v_debits,v_credits
  from jsonb_to_recordset(p_lines) as x(code text,debit numeric,credit numeric);
  if v_count<2 or v_debits<=0 or abs(v_debits-v_credits)>0.005 then
    raise exception 'Journal is not balanced: debits % and credits %',v_debits,v_credits;
  end if;
  if exists(select 1 from jsonb_to_recordset(p_lines) as x(code text,debit numeric,credit numeric)
    where x.code is null or (coalesce(x.debit,0)>0 and coalesce(x.credit,0)>0)
      or coalesce(x.debit,0)<0 or coalesce(x.credit,0)<0
      or (coalesce(x.debit,0)=0 and coalesce(x.credit,0)=0)) then
    raise exception 'Each journal line must contain either a positive debit or a positive credit';
  end if;
  select count(*) into v_missing
  from jsonb_to_recordset(p_lines) as x(code text,debit numeric,credit numeric)
  left join public.chart_of_accounts a
    on a.business_id=p_business_id and a.account_code=x.code and a.is_active
  where a.id is null;
  if v_missing>0 then raise exception 'One or more account codes are missing or inactive'; end if;

  insert into public.journal_entries(business_id,journal_date,memo,source_type,source_id,status)
  values(p_business_id,coalesce(p_journal_date,current_date),trim(p_memo),p_source_type,p_source_id,'draft')
  returning id into v_journal_id;

  insert into public.journal_lines(business_id,journal_entry_id,account_id,description,debit,credit)
  select p_business_id,v_journal_id,a.id,x.description,coalesce(x.debit,0),coalesce(x.credit,0)
  from jsonb_to_recordset(p_lines) as x(code text,debit numeric,credit numeric,description text)
  join public.chart_of_accounts a
    on a.business_id=p_business_id and a.account_code=x.code and a.is_active;

  update public.journal_entries
  set status='posted',posted_at=now(),posted_by=auth.uid()
  where id=v_journal_id;
  insert into public.audit_logs(business_id,actor_user_id,action,entity_table,entity_id,details)
  values(p_business_id,auth.uid(),'journal_posted','journal_entries',v_journal_id::text,
    jsonb_build_object('source_type',p_source_type,'source_id',p_source_id,'debits',v_debits,'credits',v_credits));
  return v_journal_id;
end;
$$;

create or replace function public.post_general_journal(
  p_business_id uuid,p_journal_date date,p_memo text,p_lines jsonb
) returns uuid language plpgsql security definer set search_path=''
as $$
begin
  if auth.uid() is null or not public.has_business_role(
    p_business_id,array['owner','admin','accountant']::public.business_role[]
  ) then raise exception 'Only an owner, administrator or accountant can post manual journals'; end if;
  return public.post_system_journal(p_business_id,p_journal_date,p_memo,'manual',null,p_lines);
end;
$$;

-- Posted journals and their lines are immutable. Corrections require a new reversing journal.
create or replace function public.protect_posted_journal()
returns trigger language plpgsql set search_path=''
as $$
declare v_status text;
begin
  if tg_table_name='journal_entries' then
    if old.status='posted' then raise exception 'Posted journals are immutable; post a reversing journal instead'; end if;
    if tg_op='DELETE' then return old; end if;
    return new;
  end if;
  select status into v_status from public.journal_entries
  where id=coalesce(old.journal_entry_id,new.journal_entry_id)
    and business_id=coalesce(old.business_id,new.business_id);
  if v_status='posted' then raise exception 'Lines in a posted journal are immutable'; end if;
  if tg_op='DELETE' then return old; end if;
  return new;
end;
$$;
drop trigger if exists trg_protect_posted_journal on public.journal_entries;
create trigger trg_protect_posted_journal before update or delete on public.journal_entries
for each row execute function public.protect_posted_journal();
drop trigger if exists trg_protect_posted_journal_lines on public.journal_lines;
create trigger trg_protect_posted_journal_lines before update or delete on public.journal_lines
for each row execute function public.protect_posted_journal();

-- Automatic accounting: new cloud-synced sales and purchases.
create or replace function public.account_for_offline_sale()
returns trigger language plpgsql security definer set search_path=''
as $$
declare v_cogs numeric(18,2); v_lines jsonb;
begin
  v_cogs:=0; -- Historical cost layers are not yet tracked; do not invent COGS.
  v_lines=jsonb_build_array(
    jsonb_build_object('code',case when lower(coalesce(new.payment_method,'')) in ('credit','on credit','accounts receivable') then '1100' else '1000' end,'debit',new.total,'credit',0,'description','Sale proceeds'),
    jsonb_build_object('code','4000','debit',0,'credit',new.total,'description','Sales revenue')
  );
  if v_cogs>0 then
    v_lines:=v_lines||jsonb_build_array(
      jsonb_build_object('code','5000','debit',v_cogs,'credit',0,'description','Cost of goods sold'),
      jsonb_build_object('code','1200','debit',0,'credit',v_cogs,'description','Inventory relieved')
    );
  end if;
  perform public.post_system_journal(new.business_id,new.transaction_date,
    'Sales transaction · '||new.receipt,'offline_sale',new.id::text,v_lines);
  return new;
end;
$$;
drop trigger if exists trg_account_for_offline_sale on public.offline_sales;
drop trigger if exists trg_account_for_offline_sale on public.offline_sales;
create constraint trigger trg_account_for_offline_sale after insert on public.offline_sales
 deferrable initially deferred for each row execute function public.account_for_offline_sale();

create or replace function public.account_for_offline_purchase()
returns trigger language plpgsql security definer set search_path=''
as $$
begin
  perform public.post_system_journal(new.business_id,new.transaction_date,
    'Purchase transaction · '||coalesce(new.supplier_name,'Supplier'),
    'offline_purchase',new.id::text,jsonb_build_array(
      jsonb_build_object('code','1200','debit',new.total,'credit',0,'description','Inventory purchased'),
      jsonb_build_object('code','2000','debit',0,'credit',new.total,'description','Supplier payable')
    ));
  return new;
end;
$$;
drop trigger if exists trg_account_for_offline_purchase on public.offline_purchases;
create trigger trg_account_for_offline_purchase after insert on public.offline_purchases
for each row execute function public.account_for_offline_purchase();

create or replace function public.account_for_expense()
returns trigger language plpgsql security definer set search_path=''
as $$
begin
  perform public.post_system_journal(new.business_id,new.expense_date,
    'Expense · '||new.category||' · '||new.description,'expense',new.id::text,jsonb_build_array(
      jsonb_build_object('code','6000','debit',new.amount,'credit',0,'description',new.category),
      jsonb_build_object('code','1000','debit',0,'credit',new.amount,'description','Cash / bank paid')
    ));
  return new;
end;
$$;
drop trigger if exists trg_account_for_expense on public.expenses;
create trigger trg_account_for_expense after insert on public.expenses
for each row execute function public.account_for_expense();

create or replace function public.account_for_sale_return()
returns trigger language plpgsql security definer set search_path=''
as $$
begin
  if new.refund_total>0 then
    perform public.post_system_journal(new.business_id,new.created_at::date,
      'Sales return · '||new.reason,'sale_return',new.id::text,jsonb_build_array(
        jsonb_build_object('code','4050','debit',new.refund_total,'credit',0,'description','Sales returns'),
        jsonb_build_object('code','1000','debit',0,'credit',new.refund_total,'description','Refund paid')
      ));
  end if;
  return new;
end;
$$;
drop trigger if exists trg_account_for_sale_return on public.offline_sale_returns;
create trigger trg_account_for_sale_return after insert on public.offline_sale_returns
for each row execute function public.account_for_sale_return();

create or replace function public.account_for_obligation_payment()
returns trigger language plpgsql security definer set search_path=''
as $$
declare v_type text; v_party text;
begin
  select obligation_type,party_name into v_type,v_party
  from public.financial_obligations where id=new.obligation_id and business_id=new.business_id;
  if v_type='receivable' then
    perform public.post_system_journal(new.business_id,new.payment_date,
      'Receivable collected · '||v_party,'obligation_payment',new.id::text,jsonb_build_array(
        jsonb_build_object('code','1000','debit',new.amount,'credit',0,'description','Cash received'),
        jsonb_build_object('code','1100','debit',0,'credit',new.amount,'description','Accounts receivable settled')
      ));
  elsif v_type='payable' then
    perform public.post_system_journal(new.business_id,new.payment_date,
      'Supplier payment · '||v_party,'obligation_payment',new.id::text,jsonb_build_array(
        jsonb_build_object('code','2000','debit',new.amount,'credit',0,'description','Accounts payable settled'),
        jsonb_build_object('code','1000','debit',0,'credit',new.amount,'description','Cash paid')
      ));
  end if;
  return new;
end;
$$;
drop trigger if exists trg_account_for_obligation_payment on public.financial_obligation_payments;
create trigger trg_account_for_obligation_payment after insert on public.financial_obligation_payments
for each row execute function public.account_for_obligation_payment();

-- Reporting functions return only the requesting member's authorised business data.
create or replace function public.accounting_trial_balance(
  p_business_id uuid,p_from date default null,p_to date default current_date
) returns table(account_code text,account_name text,account_type text,total_debit numeric,total_credit numeric,net_balance numeric)
language plpgsql security definer set search_path=''
as $$
begin
  if auth.uid() is null or not public.has_business_role(
    p_business_id,array['owner','admin','manager','accountant']::public.business_role[]
  ) then raise exception 'Not authorised to view accounting reports'; end if;
  return query
  select a.account_code,a.account_name,a.account_type,
    coalesce(sum(l.debit),0)::numeric,coalesce(sum(l.credit),0)::numeric,
    case when a.normal_balance='debit' then coalesce(sum(l.debit-l.credit),0)
         else coalesce(sum(l.credit-l.debit),0) end::numeric
  from public.chart_of_accounts a
  left join public.journal_lines l on l.account_id=a.id and l.business_id=a.business_id
  left join public.journal_entries j on j.id=l.journal_entry_id and j.business_id=l.business_id
    and j.status='posted' and j.journal_date<=coalesce(p_to,current_date)
    and (p_from is null or j.journal_date>=p_from)
  where a.business_id=p_business_id and a.is_active
  group by a.id,a.account_code,a.account_name,a.account_type,a.normal_balance
  order by a.account_code;
end;
$$;

create or replace function public.accounting_income_statement(
  p_business_id uuid,p_from date default date_trunc('month',current_date)::date,p_to date default current_date
) returns table(account_code text,account_name text,account_type text,amount numeric)
language plpgsql security definer set search_path=''
as $$
begin
  if auth.uid() is null or not public.has_business_role(
    p_business_id,array['owner','admin','manager','accountant']::public.business_role[]
  ) then raise exception 'Not authorised to view accounting reports'; end if;
  return query
  select a.account_code,a.account_name,a.account_type,
    case when a.account_type='income' then coalesce(sum(l.credit-l.debit),0)
         else coalesce(sum(l.debit-l.credit),0) end::numeric
  from public.chart_of_accounts a
  left join public.journal_lines l on l.account_id=a.id and l.business_id=a.business_id
  left join public.journal_entries j on j.id=l.journal_entry_id and j.business_id=l.business_id
    and j.status='posted' and j.journal_date between coalesce(p_from,'0001-01-01') and coalesce(p_to,current_date)
  where a.business_id=p_business_id and a.is_active and a.account_type in ('income','expense')
  group by a.id,a.account_code,a.account_name,a.account_type
  order by a.account_code;
end;
$$;

create or replace function public.accounting_balance_sheet(
  p_business_id uuid,p_as_of date default current_date
) returns table(account_code text,account_name text,account_type text,amount numeric)
language plpgsql security definer set search_path=''
as $$
begin
  if auth.uid() is null or not public.has_business_role(
    p_business_id,array['owner','admin','manager','accountant']::public.business_role[]
  ) then raise exception 'Not authorised to view accounting reports'; end if;
  return query
  select a.account_code,a.account_name,a.account_type,
    case when a.normal_balance='debit' then coalesce(sum(l.debit-l.credit),0)
         else coalesce(sum(l.credit-l.debit),0) end::numeric
  from public.chart_of_accounts a
  left join public.journal_lines l on l.account_id=a.id and l.business_id=a.business_id
  left join public.journal_entries j on j.id=l.journal_entry_id and j.business_id=l.business_id
    and j.status='posted' and j.journal_date<=coalesce(p_as_of,current_date)
  where a.business_id=p_business_id and a.is_active
    and a.account_type in ('asset','liability','equity')
  group by a.id,a.account_code,a.account_name,a.account_type,a.normal_balance
  union all
  select '3999'::text,'Accumulated earnings (unclosed)'::text,'equity'::text,
    coalesce(sum(case when a.account_type='income' then l.credit-l.debit
                      else l.debit-l.credit end),0)::numeric
  from public.chart_of_accounts a
  join public.journal_lines l on l.account_id=a.id and l.business_id=a.business_id
  join public.journal_entries j on j.id=l.journal_entry_id and j.business_id=l.business_id
  where a.business_id=p_business_id and a.account_type in ('income','expense')
    and j.status='posted' and j.journal_date<=coalesce(p_as_of,current_date)
  order by 3,1;
end;
$$;
create or replace function public.accounting_cash_flow(
  p_business_id uuid,p_from date default date_trunc('month',current_date)::date,p_to date default current_date
) returns table(account_name text,cash_in numeric,cash_out numeric,net_cash_flow numeric)
language plpgsql security definer set search_path=''
as $$
begin
  if auth.uid() is null or not public.has_business_role(
    p_business_id,array['owner','admin','manager','accountant']::public.business_role[]
  ) then raise exception 'Not authorised to view accounting reports'; end if;
  return query
  select a.account_name,coalesce(sum(l.debit),0)::numeric,coalesce(sum(l.credit),0)::numeric,
    coalesce(sum(l.debit-l.credit),0)::numeric
  from public.chart_of_accounts a
  join public.journal_lines l on l.account_id=a.id and l.business_id=a.business_id
  join public.journal_entries j on j.id=l.journal_entry_id and j.business_id=l.business_id
  where a.business_id=p_business_id and a.account_code='1000' and j.status='posted'
    and j.journal_date between coalesce(p_from,'0001-01-01') and coalesce(p_to,current_date)
  group by a.id,a.account_name;
end;
$$;

revoke all on function public.seed_default_chart_of_accounts(uuid) from public;
revoke all on function public.accounting_business_created() from public;
revoke all on function public.post_system_journal(uuid,date,text,text,text,jsonb) from public;
revoke all on function public.protect_posted_journal() from public;
revoke all on function public.account_for_offline_sale() from public;
revoke all on function public.account_for_offline_purchase() from public;
revoke all on function public.account_for_expense() from public;
revoke all on function public.account_for_sale_return() from public;
revoke all on function public.account_for_obligation_payment() from public;
revoke all on function public.initialize_accounting(uuid) from public;
revoke all on function public.post_general_journal(uuid,date,text,jsonb) from public;
revoke all on function public.accounting_trial_balance(uuid,date,date) from public;
revoke all on function public.accounting_income_statement(uuid,date,date) from public;
revoke all on function public.accounting_balance_sheet(uuid,date) from public;
revoke all on function public.accounting_cash_flow(uuid,date,date) from public;

grant execute on function public.initialize_accounting(uuid) to authenticated;
grant execute on function public.post_general_journal(uuid,date,text,jsonb) to authenticated;
grant execute on function public.accounting_trial_balance(uuid,date,date) to authenticated;
grant execute on function public.accounting_income_statement(uuid,date,date) to authenticated;
grant execute on function public.accounting_balance_sheet(uuid,date) to authenticated;
grant execute on function public.accounting_cash_flow(uuid,date,date) to authenticated;

commit;


-- Migration 019: weighted-average inventory valuation and automatic COGS.
-- White Lion SME Business OS — Migration 019
-- Moving weighted-average inventory valuation and automatic COGS posting.
-- Existing stock is opened at product.cost_price; historical sales are not rewritten.
begin;

alter table public.offline_sales add column if not exists branch_id uuid;
alter table public.offline_purchases add column if not exists branch_id uuid;

create table if not exists public.inventory_cost_balances (
  business_id uuid not null references public.businesses(id) on delete cascade,
  branch_id uuid not null,
  product_id uuid not null,
  quantity_on_hand numeric(18,3) not null default 0 check (quantity_on_hand >= 0),
  inventory_value numeric(18,2) not null default 0 check (inventory_value >= 0),
  average_unit_cost numeric(18,6) generated always as
    (case when quantity_on_hand > 0 then inventory_value / quantity_on_hand else 0 end) stored,
  updated_at timestamptz not null default now(),
  primary key (business_id,branch_id,product_id),
  foreign key (branch_id,business_id) references public.branches(id,business_id) on delete cascade,
  foreign key (product_id,business_id) references public.products(id,business_id) on delete cascade
);

create table if not exists public.inventory_cost_movements (
  id uuid primary key default gen_random_uuid(),
  business_id uuid not null references public.businesses(id) on delete cascade,
  branch_id uuid not null,
  product_id uuid not null,
  movement_type text not null check (movement_type in
    ('opening','purchase','sale','batch_receipt','adjustment_in','adjustment_out','transfer_in','transfer_out')),
  source_type text not null,
  source_id text not null,
  quantity_in numeric(18,3) not null default 0 check (quantity_in >= 0),
  quantity_out numeric(18,3) not null default 0 check (quantity_out >= 0),
  unit_cost numeric(18,6) not null default 0 check (unit_cost >= 0),
  total_cost numeric(18,2) not null default 0 check (total_cost >= 0),
  created_at timestamptz not null default now(),
  foreign key (branch_id,business_id) references public.branches(id,business_id) on delete cascade,
  foreign key (product_id,business_id) references public.products(id,business_id) on delete cascade
);

create index if not exists inventory_cost_movements_business_date_idx
  on public.inventory_cost_movements(business_id,created_at desc);
create index if not exists inventory_cost_movements_source_idx
  on public.inventory_cost_movements(business_id,source_type,source_id);
alter table public.inventory_cost_balances enable row level security;
alter table public.inventory_cost_movements enable row level security;
drop policy if exists inventory_cost_balances_finance_read on public.inventory_cost_balances;
create policy inventory_cost_balances_finance_read on public.inventory_cost_balances
for select to authenticated using (
  public.has_business_role(business_id,array['owner','admin','manager','accountant']::public.business_role[])
);
drop policy if exists inventory_cost_movements_finance_read on public.inventory_cost_movements;
create policy inventory_cost_movements_finance_read on public.inventory_cost_movements
for select to authenticated using (
  public.has_business_role(business_id,array['owner','admin','manager','accountant']::public.business_role[])
);
revoke all on public.inventory_cost_balances,public.inventory_cost_movements from anon,public,authenticated;
grant select on public.inventory_cost_balances,public.inventory_cost_movements to authenticated;

-- Opening valuation: use batch costs where available and product.cost_price for any unbatched remainder.
insert into public.inventory_cost_balances(business_id,branch_id,product_id,quantity_on_hand,inventory_value)
select bi.business_id,bi.branch_id,bi.product_id,bi.quantity_on_hand,
  round(
    case
      when coalesce(batch_cost.quantity,0)>bi.quantity_on_hand and batch_cost.quantity>0
        then (batch_cost.value/batch_cost.quantity)*bi.quantity_on_hand
      else coalesce(batch_cost.value,0)
        + greatest(bi.quantity_on_hand-coalesce(batch_cost.quantity,0),0)*p.cost_price
    end
  ,2)
from public.branch_inventory bi
join public.products p on p.id=bi.product_id and p.business_id=bi.business_id
left join lateral (
  select sum(pb.quantity_on_hand)::numeric as quantity,
         sum(pb.quantity_on_hand*pb.unit_cost)::numeric as value
  from public.product_batches pb
  where pb.business_id=bi.business_id and pb.branch_id=bi.branch_id
    and pb.product_id=bi.product_id and pb.quantity_on_hand>0
) batch_cost on true
where bi.quantity_on_hand>0
on conflict(business_id,branch_id,product_id) do nothing;

create or replace function public.set_offline_transaction_branch()
returns trigger language plpgsql security definer set search_path=''
as $$
begin
  if new.branch_id is null then
    select b.id into new.branch_id
    from public.branches b
    where b.business_id=new.business_id and b.is_active
    order by b.created_at,b.id limit 1;
  end if;
  return new;
end;
$$;
drop trigger if exists trg_set_offline_sale_branch on public.offline_sales;
create trigger trg_set_offline_sale_branch before insert on public.offline_sales
for each row execute function public.set_offline_transaction_branch();
drop trigger if exists trg_set_offline_purchase_branch on public.offline_purchases;
create trigger trg_set_offline_purchase_branch before insert on public.offline_purchases
for each row execute function public.set_offline_transaction_branch();

create or replace function public.apply_offline_purchase_inventory_cost()
returns trigger language plpgsql security definer set search_path=''
as $$
declare
  r record;
  v_qty numeric(18,3);
  v_value numeric(18,2);
  v_cost numeric(18,6);
  v_added numeric(18,3);
  v_stock numeric(18,3);
  v_before numeric(18,3);
  v_before_value numeric(18,2);
  v_branch uuid;
begin
  v_branch:=new.branch_id;
  if v_branch is null then return new; end if;
  for r in
    select product_id,sum(quantity)::numeric(18,3) as quantity,
           sum(line_total)::numeric(18,2) as line_total
    from public.offline_purchase_items
    where business_id=new.business_id and purchase_id=new.id
    group by product_id order by product_id
  loop
    select coalesce(bi.quantity_on_hand,0) into v_stock
    from public.branch_inventory bi
    where bi.business_id=new.business_id and bi.branch_id=v_branch and bi.product_id=r.product_id;
    v_stock:=coalesce(v_stock,0);
    select quantity_on_hand,inventory_value into v_before,v_before_value
    from public.inventory_cost_balances
    where business_id=new.business_id and branch_id=v_branch and product_id=r.product_id
    for update;
    if not found then
      select cost_price into v_cost from public.products
      where id=r.product_id and business_id=new.business_id;
      v_before:=greatest(v_stock-r.quantity,0);
      v_before_value:=round(v_before*coalesce(v_cost,0),2);
      insert into public.inventory_cost_balances(business_id,branch_id,product_id,quantity_on_hand,inventory_value)
      values(new.business_id,v_branch,r.product_id,v_before,v_before_value)
      on conflict(business_id,branch_id,product_id) do nothing;
      select quantity_on_hand,inventory_value into v_before,v_before_value
      from public.inventory_cost_balances
      where business_id=new.business_id and branch_id=v_branch and product_id=r.product_id
      for update;
    end if;
    v_added:=greatest(least(r.quantity,v_stock-v_before),0);
    if v_added>0 then
      v_cost:=case when r.quantity>0 then r.line_total/r.quantity else 0 end;
      v_value:=round(v_added*v_cost,2);
      update public.inventory_cost_balances
      set quantity_on_hand=quantity_on_hand+v_added,
          inventory_value=inventory_value+v_value,updated_at=now()
      where business_id=new.business_id and branch_id=v_branch and product_id=r.product_id;
      insert into public.inventory_cost_movements(
        business_id,branch_id,product_id,movement_type,source_type,source_id,
        quantity_in,unit_cost,total_cost
      ) values(new.business_id,v_branch,r.product_id,'purchase','offline_purchases',new.id::text,
        v_added,v_cost,v_value);
    end if;
  end loop;
  return new;
end;
$$;
drop trigger if exists trg_inventory_cost_purchase on public.offline_purchases;
create constraint trigger trg_inventory_cost_purchase
after insert on public.offline_purchases deferrable initially deferred
for each row execute function public.apply_offline_purchase_inventory_cost();

create or replace function public.apply_offline_sale_inventory_cost()
returns trigger language plpgsql security definer set search_path=''
as $$
declare
  r record;
  v_branch uuid;
  v_stock numeric(18,3);
  v_qty_before numeric(18,3);
  v_value_before numeric(18,2);
  v_cost numeric(18,6);
  v_sold numeric(18,3);
  v_cogs numeric(18,2);
begin
  v_branch:=new.branch_id;
  if v_branch is null then return new; end if;
  for r in
    select product_id,sum(quantity)::numeric(18,3) as quantity
    from public.offline_sale_items
    where business_id=new.business_id and sale_id=new.id
    group by product_id order by product_id
  loop
    select coalesce(bi.quantity_on_hand,0) into v_stock
    from public.branch_inventory bi
    where bi.business_id=new.business_id and bi.branch_id=v_branch and bi.product_id=r.product_id;
    v_stock:=coalesce(v_stock,0);
    select quantity_on_hand,inventory_value into v_qty_before,v_value_before
    from public.inventory_cost_balances
    where business_id=new.business_id and branch_id=v_branch and product_id=r.product_id
    for update;
    if not found then
      select cost_price into v_cost from public.products
      where id=r.product_id and business_id=new.business_id;
      v_qty_before:=v_stock+r.quantity;
      v_value_before:=round(v_qty_before*coalesce(v_cost,0),2);
      insert into public.inventory_cost_balances(business_id,branch_id,product_id,quantity_on_hand,inventory_value)
      values(new.business_id,v_branch,r.product_id,v_qty_before,v_value_before)
      on conflict(business_id,branch_id,product_id) do nothing;
      select quantity_on_hand,inventory_value into v_qty_before,v_value_before
      from public.inventory_cost_balances
      where business_id=new.business_id and branch_id=v_branch and product_id=r.product_id
      for update;
    end if;
    -- The branch stock delta distinguishes stock-managed POS lines from service/non-stock lines.
    v_sold:=greatest(least(r.quantity,v_qty_before-v_stock),0);
    if v_sold>0 then
      if v_qty_before<=0 or v_sold>v_qty_before then
        raise exception 'Inventory cost balance is insufficient for sale of product %',r.product_id;
      end if;
      v_cost:=v_value_before/nullif(v_qty_before,0);
      v_cogs:=round(v_sold*v_cost,2);
      update public.inventory_cost_balances
      set quantity_on_hand=greatest(quantity_on_hand-v_sold,0),
          inventory_value=greatest(inventory_value-v_cogs,0),updated_at=now()
      where business_id=new.business_id and branch_id=v_branch and product_id=r.product_id;
      insert into public.inventory_cost_movements(
        business_id,branch_id,product_id,movement_type,source_type,source_id,
        quantity_out,unit_cost,total_cost
      ) values(new.business_id,v_branch,r.product_id,'sale','offline_sales',new.id::text,
        v_sold,v_cost,v_cogs);
    end if;
  end loop;
  return new;
end;
$$;
drop trigger if exists trg_account_for_offline_sale on public.offline_sales;
drop trigger if exists trg_inventory_cost_sale on public.offline_sales;
create constraint trigger trg_inventory_cost_sale
after insert on public.offline_sales deferrable initially deferred
for each row execute function public.apply_offline_sale_inventory_cost();

-- COGS journal runs after the inventory-cost trigger so both entries use the same cost snapshot.
create or replace function public.account_for_offline_sale()
returns trigger language plpgsql security definer set search_path=''
as $$
declare
  v_cogs numeric(18,2);
  v_lines jsonb;
begin
  select coalesce(sum(total_cost),0) into v_cogs
  from public.inventory_cost_movements
  where business_id=new.business_id and source_type='offline_sales'
    and source_id=new.id::text and movement_type='sale';
  v_lines:=jsonb_build_array(
    jsonb_build_object('code',case when lower(coalesce(new.payment_method,'')) in ('credit','on credit','accounts receivable') then '1100' else '1000' end,
      'debit',new.total,'credit',0,'description','Sale proceeds'),
    jsonb_build_object('code','4000','debit',0,'credit',new.total,'description','Sales revenue')
  );
  if v_cogs>0 then
    v_lines:=v_lines||jsonb_build_array(
      jsonb_build_object('code','5000','debit',v_cogs,'credit',0,'description','Cost of goods sold'),
      jsonb_build_object('code','1200','debit',0,'credit',v_cogs,'description','Inventory relieved')
    );
  end if;
  perform public.post_system_journal(new.business_id,new.transaction_date,
    'Sales transaction · '||new.receipt,'offline_sale',new.id::text,v_lines);
  return new;
end;
$$;
create constraint trigger trg_z_account_for_offline_sale
after insert on public.offline_sales deferrable initially deferred
for each row execute function public.account_for_offline_sale();

create or replace function public.apply_product_batch_inventory_cost()
returns trigger language plpgsql security definer set search_path=''
as $$
declare
  v_delta numeric(18,3);
  v_before numeric(18,3);
  v_value numeric(18,2);
  v_cost numeric(18,6);
begin
  v_delta:=greatest(new.quantity_on_hand-coalesce(old.quantity_on_hand,0),0);
  if v_delta<=0 then return new; end if;
  select quantity_on_hand,inventory_value into v_before,v_value
  from public.inventory_cost_balances
  where business_id=new.business_id and branch_id=new.branch_id and product_id=new.product_id
  for update;
  if not found then
    select greatest(coalesce(bi.quantity_on_hand,0)-v_delta,0)*p.cost_price,
           greatest(coalesce(bi.quantity_on_hand,0)-v_delta,0)
      into v_value,v_before
    from public.products p
    left join public.branch_inventory bi on bi.business_id=p.business_id
      and bi.branch_id=new.branch_id and bi.product_id=p.id
    where p.id=new.product_id and p.business_id=new.business_id;
    insert into public.inventory_cost_balances(business_id,branch_id,product_id,quantity_on_hand,inventory_value)
    values(new.business_id,new.branch_id,new.product_id,coalesce(v_before,0),coalesce(v_value,0))
    on conflict(business_id,branch_id,product_id) do nothing;
    select quantity_on_hand,inventory_value into v_before,v_value
    from public.inventory_cost_balances
    where business_id=new.business_id and branch_id=new.branch_id and product_id=new.product_id
    for update;
  end if;
  v_cost:=new.unit_cost;
  update public.inventory_cost_balances
  set quantity_on_hand=quantity_on_hand+v_delta,
      inventory_value=inventory_value+round(v_delta*v_cost,2),updated_at=now()
  where business_id=new.business_id and branch_id=new.branch_id and product_id=new.product_id;
  insert into public.inventory_cost_movements(
    business_id,branch_id,product_id,movement_type,source_type,source_id,quantity_in,unit_cost,total_cost
  ) values(new.business_id,new.branch_id,new.product_id,'batch_receipt','product_batches',new.id::text,
    v_delta,v_cost,round(v_delta*v_cost,2));
  return new;
end;
$$;
drop trigger if exists trg_inventory_cost_batch on public.product_batches;
create constraint trigger trg_inventory_cost_batch
after insert or update on public.product_batches deferrable initially deferred
for each row execute function public.apply_product_batch_inventory_cost();

create or replace function public.apply_stock_adjustment_inventory_cost()
returns trigger language plpgsql security definer set search_path=''
as $$
declare
  v_qty numeric(18,3);
  v_value numeric(18,2);
  v_cost numeric(18,6);
  v_amount numeric(18,2);
  v_product_cost numeric(18,6);
begin
  if old.status='approved' or new.status<>'approved' then return new; end if;
  select quantity_on_hand,inventory_value into v_qty,v_value
  from public.inventory_cost_balances
  where business_id=new.business_id and branch_id=new.branch_id and product_id=new.product_id
  for update;
  if not found then
    select cost_price into v_product_cost from public.products
    where id=new.product_id and business_id=new.business_id;
    select coalesce(quantity_on_hand,0) into v_qty from public.branch_inventory
    where business_id=new.business_id and branch_id=new.branch_id and product_id=new.product_id;
    v_qty:=greatest(coalesce(v_qty,0)-case when new.adjustment_type='increase' then new.quantity else -new.quantity end,0);
    v_value:=round(v_qty*coalesce(v_product_cost,0),2);
    insert into public.inventory_cost_balances(business_id,branch_id,product_id,quantity_on_hand,inventory_value)
    values(new.business_id,new.branch_id,new.product_id,v_qty,v_value)
    on conflict(business_id,branch_id,product_id) do nothing;
    select quantity_on_hand,inventory_value into v_qty,v_value
    from public.inventory_cost_balances
    where business_id=new.business_id and branch_id=new.branch_id and product_id=new.product_id
    for update;
  end if;
  if new.adjustment_type='increase' then
    select cost_price into v_product_cost from public.products
    where id=new.product_id and business_id=new.business_id;
    v_cost:=coalesce(v_product_cost,0);
    v_amount:=round(new.quantity*v_cost,2);
    update public.inventory_cost_balances
    set quantity_on_hand=quantity_on_hand+new.quantity,inventory_value=inventory_value+v_amount,updated_at=now()
    where business_id=new.business_id and branch_id=new.branch_id and product_id=new.product_id;
    insert into public.inventory_cost_movements(business_id,branch_id,product_id,movement_type,source_type,source_id,quantity_in,unit_cost,total_cost)
    values(new.business_id,new.branch_id,new.product_id,'adjustment_in','stock_adjustments',new.id::text,new.quantity,v_cost,v_amount);
    if v_amount>0 then
      perform public.post_system_journal(new.business_id,current_date,'Stock increase adjustment','stock_adjustment',new.id::text,
        jsonb_build_array(jsonb_build_object('code','1200','debit',v_amount,'credit',0,'description','Inventory adjustment'),
                          jsonb_build_object('code','4100','debit',0,'credit',v_amount,'description','Stock adjustment gain')));
    end if;
  else
    if coalesce(v_qty,0)<new.quantity then raise exception 'Inventory valuation balance is insufficient for stock decrease'; end if;
    v_cost:=case when v_qty>0 then v_value/v_qty else 0 end;
    v_amount:=round(new.quantity*v_cost,2);
    update public.inventory_cost_balances
    set quantity_on_hand=greatest(quantity_on_hand-new.quantity,0),inventory_value=greatest(inventory_value-v_amount,0),updated_at=now()
    where business_id=new.business_id and branch_id=new.branch_id and product_id=new.product_id;
    insert into public.inventory_cost_movements(business_id,branch_id,product_id,movement_type,source_type,source_id,quantity_out,unit_cost,total_cost)
    values(new.business_id,new.branch_id,new.product_id,'adjustment_out','stock_adjustments',new.id::text,new.quantity,v_cost,v_amount);
    if v_amount>0 then
      perform public.post_system_journal(new.business_id,current_date,'Stock decrease / shrinkage adjustment','stock_adjustment',new.id::text,
        jsonb_build_array(jsonb_build_object('code','6000','debit',v_amount,'credit',0,'description','Inventory shrinkage'),
                          jsonb_build_object('code','1200','debit',0,'credit',v_amount,'description','Inventory adjustment')));
    end if;
  end if;
  return new;
end;
$$;
drop trigger if exists trg_inventory_cost_adjustment on public.stock_adjustments;
create trigger trg_inventory_cost_adjustment after update of status on public.stock_adjustments
for each row execute function public.apply_stock_adjustment_inventory_cost();

create or replace function public.apply_branch_transfer_inventory_cost()
returns trigger language plpgsql security definer set search_path=''
as $$
declare
  r record;
  v_qty numeric(18,3);
  v_value numeric(18,2);
  v_cost numeric(18,6);
  v_dest_qty numeric(18,3);
  v_dest_value numeric(18,2);
  v_product_cost numeric(18,6);
begin
  if old.status='approved' or new.status<>'approved' then return new; end if;
  for r in
    select product_id,sum(quantity)::numeric(18,3) as quantity
    from public.branch_stock_transfer_items
    where transfer_id=new.id and business_id=new.business_id
    group by product_id order by product_id
  loop
    select quantity_on_hand,inventory_value into v_qty,v_value
    from public.inventory_cost_balances
    where business_id=new.business_id and branch_id=new.source_branch_id and product_id=r.product_id
    for update;
    if not found then
      select cost_price into v_product_cost from public.products where id=r.product_id and business_id=new.business_id;
      select coalesce(quantity_on_hand,0)+r.quantity into v_qty from public.branch_inventory
      where business_id=new.business_id and branch_id=new.source_branch_id and product_id=r.product_id;
      v_qty:=coalesce(v_qty,r.quantity);
      v_value:=round(v_qty*coalesce(v_product_cost,0),2);
      insert into public.inventory_cost_balances(business_id,branch_id,product_id,quantity_on_hand,inventory_value)
      values(new.business_id,new.source_branch_id,r.product_id,v_qty,v_value)
      on conflict(business_id,branch_id,product_id) do nothing;
      select quantity_on_hand,inventory_value into v_qty,v_value from public.inventory_cost_balances
      where business_id=new.business_id and branch_id=new.source_branch_id and product_id=r.product_id for update;
    end if;
    if v_qty<r.quantity then raise exception 'Inventory cost balance is insufficient for branch transfer'; end if;
    v_cost:=case when v_qty>0 then v_value/v_qty else 0 end;
    v_value:=round(r.quantity*v_cost,2);
    update public.inventory_cost_balances
    set quantity_on_hand=greatest(quantity_on_hand-r.quantity,0),
        inventory_value=greatest(inventory_value-v_value,0),updated_at=now()
    where business_id=new.business_id and branch_id=new.source_branch_id and product_id=r.product_id;
    insert into public.inventory_cost_movements(business_id,branch_id,product_id,movement_type,source_type,source_id,quantity_out,unit_cost,total_cost)
    values(new.business_id,new.source_branch_id,r.product_id,'transfer_out','branch_stock_transfers',new.id::text,r.quantity,v_cost,v_value);

    select quantity_on_hand,inventory_value into v_dest_qty,v_dest_value
    from public.inventory_cost_balances
    where business_id=new.business_id and branch_id=new.destination_branch_id and product_id=r.product_id
    for update;
    if not found then
      select cost_price into v_product_cost from public.products where id=r.product_id and business_id=new.business_id;
      select greatest(coalesce(quantity_on_hand,0)-r.quantity,0) into v_dest_qty
      from public.branch_inventory where business_id=new.business_id and branch_id=new.destination_branch_id and product_id=r.product_id;
      v_dest_qty:=coalesce(v_dest_qty,0);
      v_dest_value:=round(v_dest_qty*coalesce(v_product_cost,0),2);
      insert into public.inventory_cost_balances(business_id,branch_id,product_id,quantity_on_hand,inventory_value)
      values(new.business_id,new.destination_branch_id,r.product_id,v_dest_qty,v_dest_value)
      on conflict(business_id,branch_id,product_id) do nothing;
      select quantity_on_hand,inventory_value into v_dest_qty,v_dest_value from public.inventory_cost_balances
      where business_id=new.business_id and branch_id=new.destination_branch_id and product_id=r.product_id for update;
    end if;
    update public.inventory_cost_balances
    set quantity_on_hand=quantity_on_hand+r.quantity,inventory_value=inventory_value+v_value,updated_at=now()
    where business_id=new.business_id and branch_id=new.destination_branch_id and product_id=r.product_id;
    insert into public.inventory_cost_movements(business_id,branch_id,product_id,movement_type,source_type,source_id,quantity_in,unit_cost,total_cost)
    values(new.business_id,new.destination_branch_id,r.product_id,'transfer_in','branch_stock_transfers',new.id::text,r.quantity,v_cost,v_value);
  end loop;
  return new;
end;
$$;
drop trigger if exists trg_inventory_cost_transfer on public.branch_stock_transfers;
create trigger trg_inventory_cost_transfer after update of status on public.branch_stock_transfers
for each row execute function public.apply_branch_transfer_inventory_cost();

create or replace function public.inventory_valuation_report(p_business_id uuid)
returns table(branch_name text,product_name text,sku text,quantity_on_hand numeric,average_unit_cost numeric,inventory_value numeric)
language plpgsql security definer set search_path=''
as $$
begin
  if auth.uid() is null or not public.has_business_role(
    p_business_id,array['owner','admin','manager','accountant']::public.business_role[]
  ) then raise exception 'Not authorised to view inventory valuation'; end if;
  return query
  select b.name,p.name,p.sku,cb.quantity_on_hand,cb.average_unit_cost,cb.inventory_value
  from public.inventory_cost_balances cb
  join public.branches b on b.id=cb.branch_id and b.business_id=cb.business_id
  join public.products p on p.id=cb.product_id and p.business_id=cb.business_id
  where cb.business_id=p_business_id
  order by b.name,p.name;
end;
$$;
revoke all on function public.inventory_valuation_report(uuid) from public;
grant execute on function public.inventory_valuation_report(uuid) to authenticated;

commit;

