-- White Lion SME Business OS — Migration 010
-- Branch-scoped transaction posting, transfer rejection, and branch stock write controls.
-- Legacy transactions remain unchanged; new postings must name an active branch.

begin;

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

commit;
