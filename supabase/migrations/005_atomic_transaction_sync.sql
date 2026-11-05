-- White Lion SME Business OS — Phase 2 atomic transaction sync
-- Sales and purchases are stored in dedicated cloud transaction tables.
-- Every transaction is posted atomically with inventory changes and idempotency receipt.
begin;

create table if not exists public.offline_sales (
  id uuid primary key default gen_random_uuid(),
  business_id uuid not null references public.businesses(id) on delete cascade,
  client_transaction_id text not null,
  receipt text not null,
  transaction_date date not null default current_date,
  customer_name text,
  payment_method text not null default 'cash',
  total numeric(14,2) not null check (total >= 0),
  synced_by uuid not null default auth.uid() references auth.users(id),
  created_at timestamptz not null default now(),
  unique (business_id, client_transaction_id)
);
create table if not exists public.offline_sale_items (
  id uuid primary key default gen_random_uuid(),
  business_id uuid not null references public.businesses(id) on delete cascade,
  sale_id uuid not null references public.offline_sales(id) on delete cascade,
  product_id uuid not null references public.products(id),
  product_name text not null,
  quantity numeric(14,3) not null check (quantity > 0),
  unit_price numeric(14,2) not null check (unit_price >= 0),
  line_total numeric(14,2) not null check (line_total >= 0)
);
create table if not exists public.offline_purchases (
  id uuid primary key default gen_random_uuid(),
  business_id uuid not null references public.businesses(id) on delete cascade,
  client_transaction_id text not null,
  transaction_date date not null default current_date,
  supplier_name text,
  total numeric(14,2) not null check (total >= 0),
  synced_by uuid not null default auth.uid() references auth.users(id),
  created_at timestamptz not null default now(),
  unique (business_id, client_transaction_id)
);
create table if not exists public.offline_purchase_items (
  id uuid primary key default gen_random_uuid(),
  business_id uuid not null references public.businesses(id) on delete cascade,
  purchase_id uuid not null references public.offline_purchases(id) on delete cascade,
  product_id uuid not null references public.products(id),
  product_name text not null,
  quantity numeric(14,3) not null check (quantity > 0),
  unit_cost numeric(14,2) not null check (unit_cost >= 0),
  line_total numeric(14,2) not null check (line_total >= 0)
);

alter table public.offline_sales enable row level security;
alter table public.offline_sale_items enable row level security;
alter table public.offline_purchases enable row level security;
alter table public.offline_purchase_items enable row level security;

drop policy if exists offline_sales_member_read on public.offline_sales;
create policy offline_sales_member_read on public.offline_sales for select to authenticated
 using (public.is_business_member(business_id));
drop policy if exists offline_sale_items_member_read on public.offline_sale_items;
create policy offline_sale_items_member_read on public.offline_sale_items for select to authenticated
 using (public.is_business_member(business_id));
drop policy if exists offline_purchases_member_read on public.offline_purchases;
create policy offline_purchases_member_read on public.offline_purchases for select to authenticated
 using (public.is_business_member(business_id));
drop policy if exists offline_purchase_items_member_read on public.offline_purchase_items;
create policy offline_purchase_items_member_read on public.offline_purchase_items for select to authenticated
 using (public.is_business_member(business_id));

create or replace function public.sync_local_transaction(
  p_business_id uuid,
  p_event_id text,
  p_transaction_type text,
  p_transaction jsonb
) returns jsonb
language plpgsql security definer
set search_path = ''
as $$
declare
  v_branch uuid;
  v_product uuid;
  v_sale uuid;
  v_purchase uuid;
  v_item jsonb;
  v_qty numeric;
  v_price numeric;
  v_total numeric := 0;
  v_count integer := 0;
  v_name text;
begin
  if auth.uid() is null then raise exception 'Authentication required'; end if;
  if not public.has_business_role(p_business_id,
    array['owner','admin','manager','cashier','storekeeper','accountant']::public.business_role[]) then
    raise exception 'Not authorised to synchronise transactions';
  end if;
  if coalesce(trim(p_event_id),'') = '' then raise exception 'Transaction event ID is required'; end if;
  if p_transaction_type not in ('sales','purchases') then raise exception 'Unsupported transaction type'; end if;
  if jsonb_typeof(p_transaction->'items') <> 'array' or jsonb_array_length(p_transaction->'items') = 0 then
    raise exception 'Transaction must contain at least one item';
  end if;

  if exists(select 1 from public.offline_sync_receipts where business_id=p_business_id and event_id=p_event_id) then
    return jsonb_build_object('status','already_synced','processed',0);
  end if;

  select id into v_branch from public.branches
   where business_id=p_business_id and is_active=true order by created_at limit 1;
  if v_branch is null then raise exception 'No active branch found for this business'; end if;

  if p_transaction_type='sales' then
    insert into public.offline_sales(business_id,client_transaction_id,receipt,transaction_date,customer_name,payment_method,total)
    values(p_business_id,p_transaction->>'client_transaction_id',
      coalesce(nullif(p_transaction->>'receipt',''), 'WL-'||substr(p_event_id,1,12)),
      coalesce(nullif(p_transaction->>'transaction_date','')::date,current_date),
      nullif(p_transaction->>'customer_name',''),
      coalesce(nullif(p_transaction->>'payment_method',''),'cash'),
      greatest(coalesce((p_transaction->>'total')::numeric,0),0))
    returning id into v_sale;

    for v_item in select value from jsonb_array_elements(p_transaction->'items') loop
      select id into v_product from public.products
       where business_id=p_business_id and client_record_id=v_item->>'product_client_record_id'
       for update;
      if v_product is null then raise exception 'Product is not synced to this workspace'; end if;
      v_qty := (v_item->>'quantity')::numeric;
      v_price := greatest(coalesce((v_item->>'unit_price')::numeric,0),0);
      if v_qty is null or v_qty <= 0 then raise exception 'Invalid sale quantity'; end if;
      update public.branch_inventory set quantity_on_hand=quantity_on_hand-v_qty,updated_at=now()
       where business_id=p_business_id and branch_id=v_branch and product_id=v_product and quantity_on_hand>=v_qty;
      if not found then raise exception 'Insufficient cloud stock for product %', coalesce(v_item->>'product_name',''); end if;
      v_total := v_total + round(v_qty*v_price,2);
      insert into public.offline_sale_items(business_id,sale_id,product_id,product_name,quantity,unit_price,line_total)
      values(p_business_id,v_sale,v_product,coalesce(v_item->>'product_name','Product'),v_qty,v_price,round(v_qty*v_price,2));
      v_count := v_count + 1;
    end loop;
  else
    insert into public.offline_purchases(business_id,client_transaction_id,transaction_date,supplier_name,total)
    values(p_business_id,p_transaction->>'client_transaction_id',
      coalesce(nullif(p_transaction->>'transaction_date','')::date,current_date),
      nullif(p_transaction->>'supplier_name',''),
      greatest(coalesce((p_transaction->>'total')::numeric,0),0))
    returning id into v_purchase;

    for v_item in select value from jsonb_array_elements(p_transaction->'items') loop
      select id into v_product from public.products
       where business_id=p_business_id and client_record_id=v_item->>'product_client_record_id'
       for update;
      if v_product is null then raise exception 'Product is not synced to this workspace'; end if;
      v_qty := (v_item->>'quantity')::numeric;
      v_price := greatest(coalesce((v_item->>'unit_cost')::numeric,0),0);
      if v_qty is null or v_qty <= 0 then raise exception 'Invalid purchase quantity'; end if;
      insert into public.branch_inventory(business_id,branch_id,product_id,quantity_on_hand)
      values(p_business_id,v_branch,v_product,v_qty)
      on conflict(branch_id,product_id) do update
       set quantity_on_hand=public.branch_inventory.quantity_on_hand+excluded.quantity_on_hand,updated_at=now();
      v_total := v_total + round(v_qty*v_price,2);
      insert into public.offline_purchase_items(business_id,purchase_id,product_id,product_name,quantity,unit_cost,line_total)
      values(p_business_id,v_purchase,v_product,coalesce(v_item->>'product_name','Product'),v_qty,v_price,round(v_qty*v_price,2));
      v_count := v_count + 1;
    end loop;
  end if;

  insert into public.offline_sync_receipts(business_id,event_id,record_type,record_count)
   values(p_business_id,p_event_id,p_transaction_type,v_count);
  return jsonb_build_object('status','synced','processed',v_count,'transaction_id',coalesce(v_sale,v_purchase));
end;
$$;
revoke all on function public.sync_local_transaction(uuid,text,text,jsonb) from public;
grant execute on function public.sync_local_transaction(uuid,text,text,jsonb) to authenticated;

commit;
