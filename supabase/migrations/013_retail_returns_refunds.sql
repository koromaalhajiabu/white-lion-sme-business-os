-- White Lion SME Business OS — Migration 013
-- Controlled Retail Returns & Refunds with original-sale linkage, stock restoration and audit trail.
begin;

create table if not exists public.offline_sale_returns (
  id uuid primary key default gen_random_uuid(),
  business_id uuid not null references public.businesses(id) on delete cascade,
  sale_id uuid not null references public.offline_sales(id) on delete restrict,
  branch_id uuid not null,
  client_return_id text not null,
  reason text not null,
  refund_method text not null default 'cash',
  refund_total numeric(14,2) not null check (refund_total >= 0),
  created_by uuid not null default auth.uid() references auth.users(id),
  created_at timestamptz not null default now(),
  constraint offline_sale_returns_branch_fk foreign key(branch_id,business_id)
    references public.branches(id,business_id) on delete restrict,
  constraint offline_sale_returns_unique unique(business_id,client_return_id),
  constraint offline_sale_returns_sale_fk foreign key(sale_id)
    references public.offline_sales(id) on delete restrict
);

create table if not exists public.offline_sale_return_items (
  id uuid primary key default gen_random_uuid(),
  business_id uuid not null references public.businesses(id) on delete cascade,
  return_id uuid not null references public.offline_sale_returns(id) on delete cascade,
  product_id uuid not null references public.products(id) on delete restrict,
  product_name text not null,
  quantity numeric(14,3) not null check (quantity > 0),
  unit_price numeric(14,2) not null check (unit_price >= 0),
  refund_amount numeric(14,2) not null check (refund_amount >= 0),
  restocked boolean not null default false
);

create index if not exists offline_sale_returns_sale_idx
  on public.offline_sale_returns(business_id,sale_id,created_at desc);
create index if not exists offline_sale_return_items_return_idx
  on public.offline_sale_return_items(return_id);

alter table public.offline_sale_returns enable row level security;
alter table public.offline_sale_return_items enable row level security;

drop policy if exists offline_sale_returns_member_read on public.offline_sale_returns;
create policy offline_sale_returns_member_read on public.offline_sale_returns
for select to authenticated using (public.is_business_member(business_id));

drop policy if exists offline_sale_return_items_member_read on public.offline_sale_return_items;
create policy offline_sale_return_items_member_read on public.offline_sale_return_items
for select to authenticated using (public.is_business_member(business_id));

revoke all on public.offline_sale_returns, public.offline_sale_return_items from anon, public, authenticated;
grant select on public.offline_sale_returns, public.offline_sale_return_items to authenticated;

create or replace function public.sync_sale_return(
  p_business_id uuid,
  p_branch_id uuid,
  p_client_return_id text,
  p_sale_client_transaction_id text,
  p_reason text,
  p_refund_method text,
  p_items jsonb
) returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_role public.business_role;
  v_sale public.offline_sales%rowtype;
  v_return uuid;
  v_item jsonb;
  v_product uuid;
  v_name text;
  v_qty numeric;
  v_price numeric;
  v_sold numeric;
  v_already_returned numeric;
  v_refund numeric;
  v_total numeric := 0;
  v_restock boolean;
  v_batch text;
begin
  if auth.uid() is null then raise exception 'Authentication required'; end if;
  if coalesce(trim(p_client_return_id),'') = '' then raise exception 'Return reference is required'; end if;
  if coalesce(trim(p_reason),'') = '' then raise exception 'Return reason is required'; end if;
  if p_items is null or jsonb_typeof(p_items) <> 'array' or jsonb_array_length(p_items) = 0 then
    raise exception 'Select at least one item to return';
  end if;

  select bm.role into v_role
  from public.business_members bm
  where bm.business_id=p_business_id and bm.user_id=auth.uid() and bm.is_active=true;
  if not found or v_role is null or v_role not in ('owner','admin','manager','cashier') then
    raise exception 'Your role cannot process sales returns';
  end if;

  select * into v_sale
  from public.offline_sales s
  where s.business_id=p_business_id
    and s.client_transaction_id=p_sale_client_transaction_id
  for update;
  if not found then raise exception 'Original sale is not available in the cloud yet'; end if;
  if v_sale.branch_id is null or p_branch_id is null or v_sale.branch_id <> p_branch_id then
    raise exception 'Return must be processed at the original sale branch; legacy sales without a saved branch cannot be returned through this workflow';
  end if;

  if v_role='cashier' and not exists (
    select 1 from public.branch_members bm
    where bm.business_id=p_business_id and bm.branch_id=p_branch_id
      and bm.user_id=auth.uid() and bm.is_active=true
  ) then raise exception 'You are not assigned to the original sale branch'; end if;

  if exists(
    select 1 from jsonb_array_elements(p_items) x
    group by x.value->>'product_client_record_id'
    having count(*)>1
  ) then raise exception 'Submit each returned product only once per return'; end if;

  if exists(select 1 from public.offline_sale_returns r
    where r.business_id=p_business_id and r.client_return_id=p_client_return_id) then
    return jsonb_build_object('status','already_processed','return_id',
      (select r.id from public.offline_sale_returns r where r.business_id=p_business_id and r.client_return_id=p_client_return_id));
  end if;

  for v_item in select value from jsonb_array_elements(p_items) loop
    select p.id,p.name into v_product,v_name
    from public.products p
    where p.business_id=p_business_id
      and p.client_record_id=v_item->>'product_client_record_id';
    if v_product is null then raise exception 'A returned product is not available in this business'; end if;

    v_qty := (v_item->>'quantity')::numeric;
    if v_qty is null or v_qty<=0 then raise exception 'Return quantity must be greater than zero'; end if;

    select coalesce(sum(si.quantity),0) into v_sold
    from public.offline_sale_items si
    where si.business_id=p_business_id and si.sale_id=v_sale.id and si.product_id=v_product;

    select coalesce(sum(ri.quantity),0) into v_already_returned
    from public.offline_sale_return_items ri
    join public.offline_sale_returns rr on rr.id=ri.return_id
    where ri.business_id=p_business_id and rr.sale_id=v_sale.id and ri.product_id=v_product;

    if v_qty > v_sold-v_already_returned then
      raise exception 'Return quantity exceeds the remaining quantity sold for % (remaining %)',coalesce(v_name,'product'),greatest(v_sold-v_already_returned,0);
    end if;

    select coalesce(sum(si.line_total),0)/nullif(sum(si.quantity),0)
      into v_price
    from public.offline_sale_items si
    where si.business_id=p_business_id and si.sale_id=v_sale.id and si.product_id=v_product;

    v_price := coalesce(v_price,0);
    v_refund := round(v_qty*v_price*case when coalesce(v_sale.subtotal,0)>0 then v_sale.total/v_sale.subtotal else 1 end,2);
    v_total := v_total+v_refund;
  end loop;

  insert into public.offline_sale_returns(
    business_id,sale_id,branch_id,client_return_id,reason,refund_method,refund_total
  ) values (
    p_business_id,v_sale.id,p_branch_id,p_client_return_id,trim(p_reason),
    coalesce(nullif(trim(p_refund_method),''),'cash'),round(v_total,2)
  ) returning id into v_return;

  for v_item in select value from jsonb_array_elements(p_items) loop
    select p.id,p.name into v_product,v_name
    from public.products p
    where p.business_id=p_business_id
      and p.client_record_id=v_item->>'product_client_record_id';
    v_qty := (v_item->>'quantity')::numeric;
    select coalesce(sum(si.line_total),0)/nullif(sum(si.quantity),0)
      into v_price
    from public.offline_sale_items si
    where si.business_id=p_business_id and si.sale_id=v_sale.id and si.product_id=v_product;
    v_price := coalesce(v_price,0);
    v_refund := round(v_qty*v_price*case when coalesce(v_sale.subtotal,0)>0 then v_sale.total/v_sale.subtotal else 1 end,2);
    v_restock := coalesce((v_item->>'restock')::boolean,false);

    insert into public.offline_sale_return_items(
      business_id,return_id,product_id,product_name,quantity,unit_price,refund_amount,restocked
    ) values(p_business_id,v_return,v_product,coalesce(nullif(v_item->>'product_name',''),v_name),
      v_qty,v_price,v_refund,v_restock);

    if v_restock then
      insert into public.branch_inventory(business_id,branch_id,product_id,quantity_on_hand)
      values(p_business_id,p_branch_id,v_product,v_qty)
      on conflict(branch_id,product_id) do update
        set quantity_on_hand=public.branch_inventory.quantity_on_hand+excluded.quantity_on_hand,
            updated_at=now();

      -- Returned stock is recorded as a distinct, non-expiring return batch
      -- when the product uses batch tracking; original batch identity is not inferred.
      if exists(select 1 from public.product_batches pb
        where pb.business_id=p_business_id and pb.branch_id=p_branch_id and pb.product_id=v_product) then
        v_batch := 'RET-'||substr(replace(p_client_return_id,'-',''),1,20)||'-'||substr(replace(v_product::text,'-',''),1,8);
        insert into public.product_batches(
          business_id,branch_id,product_id,batch_number,expiry_date,quantity_on_hand,unit_cost
        )
        select p_business_id,p_branch_id,v_product,v_batch,null,v_qty,coalesce(p.cost_price,0)
        from public.products p where p.id=v_product
        on conflict(branch_id,product_id,batch_number) do update
          set quantity_on_hand=public.product_batches.quantity_on_hand+excluded.quantity_on_hand,
              updated_at=now();
      end if;
    end if;
  end loop;

  insert into public.audit_logs(business_id,actor_user_id,action,entity_table,entity_id,details)
  values(p_business_id,auth.uid(),'sale_return_processed','offline_sale_returns',v_return::text,
    jsonb_build_object('sale_id',v_sale.id,'receipt',v_sale.receipt,'reason',trim(p_reason),
      'refund_method',coalesce(nullif(trim(p_refund_method),''),'cash'),
      'refund_total',round(v_total,2),'items',p_items));

  return jsonb_build_object('status','processed','return_id',v_return,'sale_receipt',v_sale.receipt,
    'refund_total',round(v_total,2));
end;
$$;

revoke all on function public.sync_sale_return(uuid,uuid,text,text,text,text,jsonb) from public;
grant execute on function public.sync_sale_return(uuid,uuid,text,text,text,text,jsonb) to authenticated;

commit;
