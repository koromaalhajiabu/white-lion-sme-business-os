-- White Lion SME Business OS — offline record sync foundation
-- Phase 1: idempotent master-data and expense sync. Sales/purchases are deliberately
-- excluded until their atomic posting RPCs support client idempotency.
begin;

alter table public.products add column if not exists client_record_id text;
alter table public.customers add column if not exists client_record_id text;
alter table public.suppliers add column if not exists client_record_id text;
alter table public.expenses add column if not exists client_record_id text;

create unique index if not exists products_business_client_record_uidx
  on public.products(business_id, client_record_id) where client_record_id is not null;
create unique index if not exists customers_business_client_record_uidx
  on public.customers(business_id, client_record_id) where client_record_id is not null;
create unique index if not exists suppliers_business_client_record_uidx
  on public.suppliers(business_id, client_record_id) where client_record_id is not null;
create unique index if not exists expenses_business_client_record_uidx
  on public.expenses(business_id, client_record_id) where client_record_id is not null;

create table if not exists public.offline_sync_receipts (
  business_id uuid not null references public.businesses(id) on delete cascade,
  event_id text not null,
  record_type text not null,
  record_count integer not null default 0,
  synced_by uuid not null default auth.uid() references auth.users(id),
  created_at timestamptz not null default now(),
  primary key (business_id, event_id)
);
alter table public.offline_sync_receipts enable row level security;
drop policy if exists offline_sync_receipts_member_read on public.offline_sync_receipts;
create policy offline_sync_receipts_member_read on public.offline_sync_receipts
  for select to authenticated using (public.is_business_member(business_id));

create or replace function public.sync_local_records(
  p_business_id uuid,
  p_event_id text,
  p_record_type text,
  p_records jsonb
) returns jsonb
language plpgsql security definer
set search_path = ''
as $$
declare
  r jsonb;
  v_branch uuid;
  v_count integer := 0;
  v_key text;
begin
  if auth.uid() is null then raise exception 'Authentication required'; end if;
  if not public.has_business_role(p_business_id,
    array['owner','admin','manager','cashier','storekeeper','accountant']::public.business_role[]) then
    raise exception 'Not authorised to synchronise records';
  end if;
  if coalesce(trim(p_event_id),'') = '' then raise exception 'Sync event ID is required'; end if;
  if p_record_type not in ('products','customers','suppliers','expenses') then
    raise exception 'Unsupported sync record type';
  end if;
  if jsonb_typeof(p_records) <> 'array' then raise exception 'Records must be a JSON array'; end if;

  if exists(select 1 from public.offline_sync_receipts
    where business_id=p_business_id and event_id=p_event_id) then
    return jsonb_build_object('status','already_synced','processed',0);
  end if;

  if p_record_type='products' then
    select id into v_branch from public.branches
      where business_id=p_business_id and is_active=true order by created_at limit 1;
    if v_branch is null then raise exception 'No active branch found'; end if;
  end if;

  for r in select value from jsonb_array_elements(p_records) loop
    v_key := nullif(r->>'client_record_id','');
    if v_key is null then raise exception 'Every record needs a stable client_record_id'; end if;

    if p_record_type='products' then
      insert into public.products(business_id,client_record_id,sku,name,category,unit,cost_price,selling_price,reorder_level,is_active)
      values(p_business_id,v_key,nullif(r->>'sku',''),coalesce(nullif(r->>'name',''),'Unnamed product'),
        nullif(r->>'category',''),coalesce(nullif(r->>'unit',''),'unit'),
        greatest(coalesce((r->>'cost_price')::numeric,0),0),
        greatest(coalesce((r->>'selling_price')::numeric,0),0),
        greatest(coalesce((r->>'reorder_level')::numeric,0),0),true)
      on conflict (business_id,client_record_id) where client_record_id is not null
      do update set sku=excluded.sku,name=excluded.name,category=excluded.category,unit=excluded.unit,
        cost_price=excluded.cost_price,selling_price=excluded.selling_price,reorder_level=excluded.reorder_level,updated_at=now();
      insert into public.branch_inventory(business_id,branch_id,product_id,quantity_on_hand)
      select p_business_id,v_branch,p.id,greatest(coalesce((r->>'quantity_on_hand')::numeric,0),0)
      from public.products p where p.business_id=p_business_id and p.client_record_id=v_key
      on conflict(branch_id,product_id) do update
        set quantity_on_hand=excluded.quantity_on_hand,updated_at=now();
    elsif p_record_type='customers' then
      insert into public.customers(business_id,client_record_id,name,phone,email,address,notes)
      values(p_business_id,v_key,coalesce(nullif(r->>'name',''),'Unnamed customer'),
        nullif(r->>'phone',''),nullif(r->>'email',''),nullif(r->>'address',''),nullif(r->>'notes',''))
      on conflict (business_id,client_record_id) where client_record_id is not null
      do update set name=excluded.name,phone=excluded.phone,email=excluded.email,address=excluded.address,notes=excluded.notes,updated_at=now();
    elsif p_record_type='suppliers' then
      insert into public.suppliers(business_id,client_record_id,name,phone,email,address,notes)
      values(p_business_id,v_key,coalesce(nullif(r->>'name',''),'Unnamed supplier'),
        nullif(r->>'phone',''),nullif(r->>'email',''),nullif(r->>'address',''),nullif(r->>'notes',''))
      on conflict (business_id,client_record_id) where client_record_id is not null
      do update set name=excluded.name,phone=excluded.phone,email=excluded.email,address=excluded.address,notes=excluded.notes,updated_at=now();
    elsif p_record_type='expenses' then
      insert into public.expenses(business_id,client_record_id,category,description,amount,payment_method,expense_date)
      values(p_business_id,v_key,coalesce(nullif(r->>'category',''),'General'),
        coalesce(nullif(r->>'description',''),'Expense'),greatest(coalesce((r->>'amount')::numeric,0.01),0.01),
        coalesce(nullif(r->>'payment_method',''),'cash'),coalesce(nullif(r->>'expense_date','')::date,current_date))
      on conflict (business_id,client_record_id) where client_record_id is not null
      do update set category=excluded.category,description=excluded.description,amount=excluded.amount,
        payment_method=excluded.payment_method,expense_date=excluded.expense_date;
    end if;
    v_count := v_count + 1;
  end loop;

  insert into public.offline_sync_receipts(business_id,event_id,record_type,record_count)
  values(p_business_id,p_event_id,p_record_type,v_count);
  return jsonb_build_object('status','synced','processed',v_count);
end;
$$;
revoke all on function public.sync_local_records(uuid,text,text,jsonb) from public;
grant execute on function public.sync_local_records(uuid,text,text,jsonb) to authenticated;

commit;
