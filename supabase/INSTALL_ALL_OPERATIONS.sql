-- WHITE LION SME BUSINESS OS
-- SINGLE INSTALLER: migrations 010 + 011
-- Run once after migrations 001–009 have been installed.
-- This file combines branch-aware transactions, staff visibility, transfers,
-- finance registers, receivables/payables, batch/expiry tracking and stock approvals.
-- Do not run the two individual migration files separately if you run this installer.

begin;

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
  if not public.has_business_role(p_business_id,array['owner','admin','manager','cashier','storekeeper','accountant']::public.business_role[]) then
    raise exception 'Active business membership and platform access required';
  end if;
  if not public.has_business_role(p_business_id,array['owner','admin','manager','cashier','storekeeper','accountant']::public.business_role[]) then
    raise exception 'Active business membership and platform access required';
  end if;
  if not found then raise exception 'Active business membership required'; end if;
  if v_role not in ('owner','admin','manager','cashier','storekeeper','accountant') then
    raise exception 'Not authorised to synchronise records';
  end if;
  if v_role='cashier' and p_record_type='products' then
    raise exception 'Cashiers cannot create products or opening stock';
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
create policy offline_sale_items_branch_read on public.offline_sale_items
for select to authenticated using (
 exists(select 1 from public.offline_sales s where s.id=offline_sale_items.sale_id and s.business_id=offline_sale_items.business_id)
);
drop policy if exists offline_purchase_items_member_read on public.offline_purchase_items;
create policy offline_purchase_items_branch_read on public.offline_purchase_items
for select to authenticated using (
 exists(select 1 from public.offline_purchases p where p.id=offline_purchase_items.purchase_id and p.business_id=offline_purchase_items.business_id)
);

drop policy if exists branch_stock_transfers_member_read on public.branch_stock_transfers;
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
  if not public.has_business_role(p_business_id,array['owner','admin','manager','cashier','storekeeper']::public.business_role[]) then
    raise exception 'Active business membership and platform access required';
  end if;
  if not public.has_business_role(p_business_id,array['owner','admin','manager','cashier','storekeeper']::public.business_role[]) then
    raise exception 'Active business membership and platform access required';
  end if;
  if not found then raise exception 'Active business membership required'; end if;

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

-- ============================================================
-- MIGRATION 011: FINANCE AND INVENTORY CONTROLS
-- ============================================================

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
  public.stock_adjustments from anon;
grant select, insert on public.cashbook_entries, public.financial_obligations to authenticated;
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
