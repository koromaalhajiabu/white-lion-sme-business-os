-- Owner-controlled approval and safe Mobile-Unlock submission gate.
begin;

alter table public.phone_unlocking_orders
  add column if not exists provider_service_id text,
  add column if not exists provider_service_type text,
  add column if not exists approval_status text not null default 'pending'
    check (approval_status in ('pending','approved','rejected')),
  add column if not exists approved_by uuid references auth.users(id),
  add column if not exists approved_at timestamptz,
  add column if not exists rejected_by uuid references auth.users(id),
  add column if not exists rejected_at timestamptz,
  add column if not exists rejection_reason text,
  add column if not exists provider_submission_status text not null default 'not_submitted'
    check (provider_submission_status in ('not_submitted','submitting','submitted','failed','unknown')),
  add column if not exists provider_submission_attempted_at timestamptz,
  add column if not exists provider_submission_message text;

create index if not exists phone_unlocking_orders_approval_idx
  on public.phone_unlocking_orders(business_id,approval_status,created_at desc);

grant insert (provider_service_id,provider_service_type) on public.phone_unlocking_orders to authenticated;
grant select on public.phone_unlocking_orders to authenticated;

create or replace function public.approve_phone_unlocking_order(
  p_business_id uuid,
  p_order_id uuid
) returns void
language plpgsql
security definer
set search_path = public, auth
as $approve$
declare
  v_order public.phone_unlocking_orders%rowtype;
begin
  if auth.uid() is null then raise exception 'Authentication required'; end if;
  if not public.has_business_role(p_business_id,array['owner']::public.business_role[]) then
    raise exception 'Only the business owner can approve phone unlocking orders';
  end if;
  select * into v_order from public.phone_unlocking_orders
   where id=p_order_id and business_id=p_business_id for update;
  if not found then raise exception 'Unlocking order not found'; end if;
  if v_order.approval_status <> 'pending' then raise exception 'This order has already been reviewed'; end if;
  if v_order.status not in ('received','quoted','awaiting_payment') then
    raise exception 'This order is not eligible for approval';
  end if;
  if v_order.amount_paid < v_order.service_price then
    raise exception 'Full customer payment is required before approval';
  end if;
  update public.phone_unlocking_orders
     set approval_status='approved',approved_by=auth.uid(),approved_at=now(),
         rejected_by=null,rejected_at=null,rejection_reason=null,updated_at=now()
   where id=p_order_id and business_id=p_business_id;
  insert into public.audit_logs(business_id,actor_user_id,action,entity_table,entity_id,details)
  values(p_business_id,auth.uid(),'phone_unlocking_order_approved','phone_unlocking_orders',
    p_order_id::text,jsonb_build_object('reference',v_order.reference,'provider_submission','requires_explicit_server_action'));
end;
$approve$;

create or replace function public.reject_phone_unlocking_order(
  p_business_id uuid,
  p_order_id uuid,
  p_reason text default null
) returns void
language plpgsql
security definer
set search_path = public, auth
as $reject$
declare
  v_order public.phone_unlocking_orders%rowtype;
begin
  if auth.uid() is null then raise exception 'Authentication required'; end if;
  if not public.has_business_role(p_business_id,array['owner']::public.business_role[]) then
    raise exception 'Only the business owner can reject phone unlocking orders';
  end if;
  select * into v_order from public.phone_unlocking_orders
   where id=p_order_id and business_id=p_business_id for update;
  if not found then raise exception 'Unlocking order not found'; end if;
  if v_order.approval_status <> 'pending' then raise exception 'This order has already been reviewed'; end if;
  if v_order.provider_submission_status <> 'not_submitted' then
    raise exception 'An order with a provider submission attempt cannot be rejected here';
  end if;
  update public.phone_unlocking_orders
     set approval_status='rejected',rejected_by=auth.uid(),rejected_at=now(),
         rejection_reason=nullif(left(trim(coalesce(p_reason,'')),500),''),
         status=case when amount_paid=0 then 'cancelled' else status end,updated_at=now()
   where id=p_order_id and business_id=p_business_id;
  insert into public.audit_logs(business_id,actor_user_id,action,entity_table,entity_id,details)
  values(p_business_id,auth.uid(),'phone_unlocking_order_rejected','phone_unlocking_orders',
    p_order_id::text,jsonb_build_object('reference',v_order.reference,'reason',left(coalesce(p_reason,''),500)));
end;
$reject$;

-- Atomically claim a provider submission. A second click/retry cannot submit the same order twice.
create or replace function public.claim_phone_unlocking_provider_submission(
  p_business_id uuid,
  p_order_id uuid
) returns jsonb
language plpgsql
security definer
set search_path = public, auth
as $claim$
declare
  v_order public.phone_unlocking_orders%rowtype;
begin
  if auth.uid() is null then raise exception 'Authentication required'; end if;
  if not public.has_business_role(p_business_id,array['owner']::public.business_role[]) then
    raise exception 'Only the business owner can submit approved provider orders';
  end if;
  select * into v_order from public.phone_unlocking_orders
   where id=p_order_id and business_id=p_business_id for update;
  if not found then raise exception 'Unlocking order not found'; end if;
  if v_order.approval_status <> 'approved' or v_order.approved_by <> auth.uid() then
    raise exception 'This order has not been approved by the signed-in business owner';
  end if;
  if v_order.amount_paid < v_order.service_price then raise exception 'Full customer payment is required'; end if;
  if v_order.provider_service_id is null or v_order.provider_service_type <> 'IMEI' then
    raise exception 'This order has no supported Mobile-Unlock IMEI service mapping';
  end if;
  if v_order.provider_submission_status <> 'not_submitted' then
    raise exception 'A provider submission has already been attempted. Reconcile its status before any retry';
  end if;
  if v_order.status in ('cancelled','failed','refunded','completed') then
    raise exception 'This order is not in a submit-ready state';
  end if;
  update public.phone_unlocking_orders
     set provider_submission_status='submitting',
         provider_submission_attempted_at=now(),
         provider_submission_message='Owner-approved submission started',
         updated_at=now()
   where id=p_order_id and business_id=p_business_id
   returning * into v_order;
  return to_jsonb(v_order);
end;
$claim$;

create or replace function public.finish_phone_unlocking_provider_submission(
  p_business_id uuid,
  p_order_id uuid,
  p_outcome text,
  p_provider_reference text default null,
  p_message text default null
) returns void
language plpgsql
security definer
set search_path = public, auth
as $finish$
declare
  v_order public.phone_unlocking_orders%rowtype;
begin
  if auth.uid() is null then raise exception 'Authentication required'; end if;
  if not public.has_business_role(p_business_id,array['owner']::public.business_role[]) then
    raise exception 'Only the business owner can finalise provider submission';
  end if;
  if p_outcome not in ('submitted','failed','unknown') then raise exception 'Invalid provider submission outcome'; end if;
  select * into v_order from public.phone_unlocking_orders
   where id=p_order_id and business_id=p_business_id for update;
  if not found then raise exception 'Unlocking order not found'; end if;
  if v_order.provider_submission_status <> 'submitting' then
    raise exception 'Order is not currently marked as submitting';
  end if;
  update public.phone_unlocking_orders
     set provider_submission_status=p_outcome,
         provider_reference=case when p_outcome='submitted' then nullif(trim(coalesce(p_provider_reference,'')),'') else provider_reference end,
         provider_submission_message=left(coalesce(p_message,''),500),
         status=case when p_outcome='submitted' then 'processing' else status end,
         provider_name=case when p_outcome='submitted' then 'Mobile-Unlock' else provider_name end,
         updated_at=now()
   where id=p_order_id and business_id=p_business_id;
  insert into public.audit_logs(business_id,actor_user_id,action,entity_table,entity_id,details)
  values(p_business_id,auth.uid(),'phone_unlocking_provider_submission_'||p_outcome,
    'phone_unlocking_orders',p_order_id::text,
    jsonb_build_object('reference',v_order.reference,'provider_reference',p_provider_reference,'message',left(coalesce(p_message,''),500)));
end;
$finish$;

revoke all on function public.approve_phone_unlocking_order(uuid,uuid) from public;
revoke all on function public.reject_phone_unlocking_order(uuid,uuid,text) from public;
revoke all on function public.claim_phone_unlocking_provider_submission(uuid,uuid) from public;
revoke all on function public.finish_phone_unlocking_provider_submission(uuid,uuid,text,text,text) from public;
grant execute on function public.approve_phone_unlocking_order(uuid,uuid) to authenticated;
grant execute on function public.reject_phone_unlocking_order(uuid,uuid,text) to authenticated;
grant execute on function public.claim_phone_unlocking_provider_submission(uuid,uuid) to authenticated;
grant execute on function public.finish_phone_unlocking_provider_submission(uuid,uuid,text,text,text) to authenticated;

commit;
