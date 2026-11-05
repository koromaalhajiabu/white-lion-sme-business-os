-- White Lion SME Business OS — Migration 011
-- Financial registers, product batches/expiry and controlled stock adjustments.
begin;

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
    references public.branches(id,business_id) on delete set null
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
    references public.branches(id,business_id) on delete set null
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
 if not found or v_role not in ('owner','admin','manager','storekeeper') then
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
 if not found or v_role not in ('owner','admin','manager') then
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

revoke all on function public.request_stock_adjustment(uuid,uuid,uuid,text,numeric,text) from public;
revoke all on function public.decide_stock_adjustment(uuid,boolean,text) from public;
grant execute on function public.request_stock_adjustment(uuid,uuid,uuid,text,numeric,text) to authenticated;
grant execute on function public.decide_stock_adjustment(uuid,boolean,text) to authenticated;

commit;
