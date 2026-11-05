-- White Lion SME Business OS — Migration 009: Multi-branch management foundation
-- Adds branch-level staff assignments and audited stock-transfer requests.
-- Existing transaction history is preserved; branch_id remains NULL for legacy transactions
-- because their original branch cannot be established safely.

begin;

alter table public.offline_sales
  add column if not exists branch_id uuid null;
alter table public.offline_purchases
  add column if not exists branch_id uuid null;

do $$
begin
  if not exists (
    select 1 from pg_constraint
    where conname = 'offline_sales_branch_business_fkey'
      and conrelid = 'public.offline_sales'::regclass
  ) then
    alter table public.offline_sales
      add constraint offline_sales_branch_business_fkey
      foreign key (branch_id, business_id)
      references public.branches(id, business_id)
      on delete set null (branch_id);
  end if;
  if not exists (
    select 1 from pg_constraint
    where conname = 'offline_purchases_branch_business_fkey'
      and conrelid = 'public.offline_purchases'::regclass
  ) then
    alter table public.offline_purchases
      add constraint offline_purchases_branch_business_fkey
      foreign key (branch_id, business_id)
      references public.branches(id, business_id)
      on delete set null (branch_id);
  end if;
end $$;

create index if not exists offline_sales_business_branch_date_idx
  on public.offline_sales(business_id, branch_id, transaction_date desc);
create index if not exists offline_purchases_business_branch_date_idx
  on public.offline_purchases(business_id, branch_id, transaction_date desc);

create table if not exists public.branch_members (
  business_id uuid not null,
  branch_id uuid not null,
  user_id uuid not null,
  assigned_by uuid null default auth.uid(),
  is_active boolean not null default true,
  created_at timestamptz not null default now(),
  primary key (branch_id, user_id),
  constraint branch_members_branch_business_fkey
    foreign key (branch_id, business_id)
    references public.branches(id, business_id) on delete cascade,
  constraint branch_members_business_user_fkey
    foreign key (business_id, user_id)
    references public.business_members(business_id, user_id) on delete cascade,
  constraint branch_members_assigned_by_fkey
    foreign key (assigned_by) references auth.users(id) on delete set null
);

create index if not exists branch_members_business_user_idx
  on public.branch_members(business_id, user_id, is_active);

alter table public.branch_members enable row level security;
drop policy if exists branch_members_read on public.branch_members;
create policy branch_members_read on public.branch_members
  for select to authenticated
  using (public.is_business_member(business_id));
drop policy if exists branch_members_manage on public.branch_members;
create policy branch_members_manage on public.branch_members
  for all to authenticated
  using (public.has_business_role(business_id, array['owner','admin','manager']::public.business_role[]))
  with check (public.has_business_role(business_id, array['owner','admin','manager']::public.business_role[]));

create table if not exists public.branch_stock_transfers (
  id uuid primary key default gen_random_uuid(),
  business_id uuid not null references public.businesses(id) on delete cascade,
  source_branch_id uuid not null,
  destination_branch_id uuid not null,
  status text not null default 'pending'
    check (status in ('pending','completed','cancelled')),
  requested_by uuid null default auth.uid() references auth.users(id) on delete set null,
  approved_by uuid null references auth.users(id) on delete set null,
  requested_at timestamptz not null default now(),
  completed_at timestamptz null,
  note text null,
  constraint branch_transfer_different_branches_check
    check (source_branch_id <> destination_branch_id),
  constraint branch_transfer_source_business_fkey
    foreign key (source_branch_id, business_id)
    references public.branches(id, business_id),
  constraint branch_transfer_destination_business_fkey
    foreign key (destination_branch_id, business_id)
    references public.branches(id, business_id)
);

create table if not exists public.branch_stock_transfer_items (
  id uuid primary key default gen_random_uuid(),
  transfer_id uuid not null references public.branch_stock_transfers(id) on delete cascade,
  business_id uuid not null references public.businesses(id) on delete cascade,
  product_id uuid not null,
  product_name text not null,
  quantity numeric(14,3) not null check (quantity > 0),
  constraint branch_transfer_item_product_business_fkey
    foreign key (product_id, business_id)
    references public.products(id, business_id)
);

create index if not exists branch_stock_transfers_business_status_idx
  on public.branch_stock_transfers(business_id, status, requested_at desc);
create index if not exists branch_stock_transfer_items_transfer_idx
  on public.branch_stock_transfer_items(transfer_id);

alter table public.branch_stock_transfers enable row level security;
alter table public.branch_stock_transfer_items enable row level security;

drop policy if exists branch_stock_transfers_member_read on public.branch_stock_transfers;
create policy branch_stock_transfers_member_read on public.branch_stock_transfers
  for select to authenticated using (public.is_business_member(business_id));
drop policy if exists branch_stock_transfer_items_member_read on public.branch_stock_transfer_items;
create policy branch_stock_transfer_items_member_read on public.branch_stock_transfer_items
  for select to authenticated using (public.is_business_member(business_id));

create or replace function public.set_branch_member_access(
  p_business_id uuid,
  p_branch_id uuid,
  p_user_id uuid,
  p_is_active boolean
) returns jsonb
language plpgsql security definer
set search_path = ''
as $$
declare
  v_role public.business_role;
begin
  if auth.uid() is null then raise exception 'Authentication required'; end if;
  if not public.has_business_role(p_business_id, array['owner','admin','manager']::public.business_role[]) then
    raise exception 'Only an owner, admin, or manager can manage branch assignments';
  end if;
  if not exists (
    select 1 from public.branches
    where id=p_branch_id and business_id=p_business_id and is_active=true
  ) then raise exception 'Active branch not found in this business'; end if;

  select role into v_role from public.business_members
  where business_id=p_business_id and user_id=p_user_id and is_active=true;
  if not found then raise exception 'User is not an active member of this business'; end if;
  if v_role='owner' then raise exception 'The business owner already has access to every branch'; end if;

  insert into public.branch_members(business_id,branch_id,user_id,assigned_by,is_active)
  values(p_business_id,p_branch_id,p_user_id,auth.uid(),p_is_active)
  on conflict(branch_id,user_id) do update
    set is_active=excluded.is_active, assigned_by=auth.uid();

  insert into public.audit_logs(business_id,actor_user_id,action,entity_table,entity_id,details)
  values(p_business_id,auth.uid(),'branch_member_access_updated','branch_members',
    p_branch_id::text,jsonb_build_object('user_id',p_user_id,'role',v_role,'is_active',p_is_active));

  return jsonb_build_object('status','updated','branch_id',p_branch_id,'user_id',p_user_id,'is_active',p_is_active);
end;
$$;

create or replace function public.request_branch_stock_transfer(
  p_business_id uuid,
  p_source_branch_id uuid,
  p_destination_branch_id uuid,
  p_items jsonb,
  p_note text default null
) returns jsonb
language plpgsql security definer
set search_path = ''
as $$
declare
  v_transfer uuid;
  v_item jsonb;
  v_product uuid;
  v_qty numeric;
  v_name text;
  v_role public.business_role;
begin
  if auth.uid() is null then raise exception 'Authentication required'; end if;
  if not public.has_business_role(p_business_id,
    array['owner','admin','manager','storekeeper']::public.business_role[]) then
    raise exception 'Not authorised to request stock transfers';
  end if;
  if p_source_branch_id=p_destination_branch_id then raise exception 'Choose two different branches'; end if;
  if jsonb_typeof(p_items)<>'array' or jsonb_array_length(p_items)=0 then
    raise exception 'Add at least one product to transfer';
  end if;
  if not exists(select 1 from public.branches where id=p_source_branch_id and business_id=p_business_id and is_active)
    or not exists(select 1 from public.branches where id=p_destination_branch_id and business_id=p_business_id and is_active) then
    raise exception 'Both branches must be active branches in this business';
  end if;

  select role into v_role from public.business_members
  where business_id=p_business_id and user_id=auth.uid() and is_active;
  if v_role not in ('owner','admin','manager') and (
    not exists(select 1 from public.branch_members where business_id=p_business_id and branch_id=p_source_branch_id and user_id=auth.uid() and is_active)
    or not exists(select 1 from public.branch_members where business_id=p_business_id and branch_id=p_destination_branch_id and user_id=auth.uid() and is_active)
  ) then raise exception 'Storekeeper must be assigned to both branches to request a transfer'; end if;

  insert into public.branch_stock_transfers(business_id,source_branch_id,destination_branch_id,note)
  values(p_business_id,p_source_branch_id,p_destination_branch_id,nullif(trim(p_note),''))
  returning id into v_transfer;

  for v_item in select value from jsonb_array_elements(p_items) loop
    v_name := coalesce(nullif(v_item->>'product_name',''),'Product');
    v_qty := (v_item->>'quantity')::numeric;
    if v_qty is null or v_qty<=0 then raise exception 'Transfer quantity must be greater than zero'; end if;
    select id into v_product from public.products
      where business_id=p_business_id and client_record_id=v_item->>'product_client_record_id' and is_active;
    if v_product is null then raise exception 'A transfer product is not synced or is inactive'; end if;
    insert into public.branch_stock_transfer_items(transfer_id,business_id,product_id,product_name,quantity)
    values(v_transfer,p_business_id,v_product,v_name,v_qty);
  end loop;

  insert into public.audit_logs(business_id,actor_user_id,action,entity_table,entity_id,details)
  values(p_business_id,auth.uid(),'branch_stock_transfer_requested','branch_stock_transfers',v_transfer::text,
    jsonb_build_object('source_branch_id',p_source_branch_id,'destination_branch_id',p_destination_branch_id,'item_count',jsonb_array_length(p_items)));

  return jsonb_build_object('status','pending_approval','transfer_id',v_transfer);
end;
$$;

create or replace function public.approve_branch_stock_transfer(
  p_transfer_id uuid
) returns jsonb
language plpgsql security definer
set search_path = ''
as $$
declare
  v_transfer public.branch_stock_transfers%rowtype;
  v_item record;
  v_role public.business_role;
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
     where branch_id=v_transfer.source_branch_id and product_id=v_item.product_id
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
  values(v_transfer.business_id,auth.uid(),'branch_stock_transfer_approved','branch_stock_transfers',p_transfer_id::text,
    jsonb_build_object('source_branch_id',v_transfer.source_branch_id,'destination_branch_id',v_transfer.destination_branch_id));

  return jsonb_build_object('status','completed','transfer_id',p_transfer_id);
end;
$$;

create or replace function public.cancel_branch_stock_transfer(
  p_transfer_id uuid
) returns jsonb
language plpgsql security definer
set search_path = ''
as $$
declare
  v_transfer public.branch_stock_transfers%rowtype;
begin
  if auth.uid() is null then raise exception 'Authentication required'; end if;
  select * into v_transfer from public.branch_stock_transfers
   where id=p_transfer_id for update;
  if not found then raise exception 'Transfer request not found'; end if;
  if v_transfer.status<>'pending' then raise exception 'Only pending transfers can be cancelled'; end if;
  if not public.has_business_role(v_transfer.business_id,
    array['owner','admin','manager']::public.business_role[])
    and v_transfer.requested_by<>auth.uid() then
    raise exception 'Not authorised to cancel this transfer';
  end if;

  update public.branch_stock_transfers set status='cancelled' where id=p_transfer_id;
  insert into public.audit_logs(business_id,actor_user_id,action,entity_table,entity_id,details)
  values(v_transfer.business_id,auth.uid(),'branch_stock_transfer_cancelled','branch_stock_transfers',p_transfer_id::text,'{}'::jsonb);

  return jsonb_build_object('status','cancelled','transfer_id',p_transfer_id);
end;
$$;

revoke all on function public.set_branch_member_access(uuid,uuid,uuid,boolean) from public;
revoke all on function public.request_branch_stock_transfer(uuid,uuid,uuid,jsonb,text) from public;
revoke all on function public.approve_branch_stock_transfer(uuid) from public;
revoke all on function public.cancel_branch_stock_transfer(uuid) from public;
grant execute on function public.set_branch_member_access(uuid,uuid,uuid,boolean) to authenticated;
grant execute on function public.request_branch_stock_transfer(uuid,uuid,uuid,jsonb,text) to authenticated;
grant execute on function public.approve_branch_stock_transfer(uuid) to authenticated;
grant execute on function public.cancel_branch_stock_transfer(uuid) to authenticated;

commit;
