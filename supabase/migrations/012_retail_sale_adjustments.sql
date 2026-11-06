-- White Lion SME Business OS — Migration 012
-- Preserve Retail POS subtotal, discount and tax in cloud sales.
begin;

alter table public.offline_sales
  add column if not exists subtotal numeric(14,2) not null default 0 check (subtotal >= 0),
  add column if not exists discount numeric(14,2) not null default 0 check (discount >= 0),
  add column if not exists tax numeric(14,2) not null default 0 check (tax >= 0);

-- Backfill existing historical sales as undiscounted, untaxed transactions.
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

commit;
