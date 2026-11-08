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
