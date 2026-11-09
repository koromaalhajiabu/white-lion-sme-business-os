-- White Lion SME OS — SaaS plans, subscription lifecycle, invoices and verified manual payments.
-- Safe additive migration: preserves existing business data and never auto-bills existing workspaces.
begin;

create table if not exists public.subscription_plans (
  code text primary key check (code in ('starter','professional','enterprise')),
  name text not null,
  description text not null default '',
  sle_monthly numeric(12,2) not null check (sle_monthly > 0),
  sle_annual numeric(12,2) not null check (sle_annual > 0),
  usd_monthly numeric(12,2) not null check (usd_monthly > 0),
  usd_annual numeric(12,2) not null check (usd_annual > 0),
  max_users integer not null check (max_users > 0),
  max_branches integer not null check (max_branches > 0),
  features jsonb not null default '[]'::jsonb,
  is_active boolean not null default true,
  display_order integer not null default 10,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

insert into public.subscription_plans
(code,name,description,sle_monthly,sle_annual,usd_monthly,usd_annual,max_users,max_branches,features,display_order)
values
('starter','Starter','Essential tools for a small business',250,2500,10,100,2,1,
 '["Sales and POS","Products and basic inventory","Purchases and suppliers","Basic business reports","Offline working"]'::jsonb,1),
('professional','Professional','More control for a growing business',600,6000,25,250,5,1,
 '["Everything in Starter","Advanced inventory and purchasing","Finance and performance reports","Customer and supplier management","Offline working and cloud sync"]'::jsonb,2),
('enterprise','Enterprise','Multi-location operations and advanced controls',1200,12000,50,500,15,5,
 '["Everything in Professional","Multi-branch operations","Branch stock transfers","Advanced administration","Priority support"]'::jsonb,3)
on conflict (code) do update set
 name=excluded.name, description=excluded.description,
 sle_monthly=excluded.sle_monthly, sle_annual=excluded.sle_annual,
 usd_monthly=excluded.usd_monthly, usd_annual=excluded.usd_annual,
 max_users=excluded.max_users, max_branches=excluded.max_branches,
 features=excluded.features, display_order=excluded.display_order, updated_at=now();

create table if not exists public.business_subscriptions (
 id uuid primary key default gen_random_uuid(),
 business_id uuid not null unique references public.businesses(id) on delete cascade,
 plan_code text not null references public.subscription_plans(code),
 status text not null default 'pending_payment'
   check (status in ('trial','pending_payment','active','past_due','grace_period','expired','cancelled','suspended')),
 currency_code text not null check (currency_code in ('SLE','USD')),
 billing_cycle text not null check (billing_cycle in ('monthly','annual')),
 current_period_start timestamptz,
 current_period_end timestamptz,
 trial_ends_at timestamptz,
 grace_until timestamptz,
 cancel_at_period_end boolean not null default false,
 notes text,
 created_at timestamptz not null default now(),
 updated_at timestamptz not null default now()
);

create table if not exists public.subscription_invoices (
 id uuid primary key default gen_random_uuid(),
 invoice_number text not null unique,
 business_id uuid not null references public.businesses(id) on delete cascade,
 subscription_id uuid references public.business_subscriptions(id) on delete set null,
 plan_code text not null references public.subscription_plans(code),
 currency_code text not null check (currency_code in ('SLE','USD')),
 billing_cycle text not null check (billing_cycle in ('monthly','annual')),
 amount_due numeric(12,2) not null check (amount_due > 0),
 status text not null default 'pending'
   check (status in ('pending','awaiting_verification','paid','void','overdue')),
 period_start timestamptz,
 period_end timestamptz,
 due_at timestamptz not null default (now() + interval '7 days'),
 paid_at timestamptz,
 created_by uuid not null references auth.users(id),
 created_at timestamptz not null default now()
);

create table if not exists public.subscription_payments (
 id uuid primary key default gen_random_uuid(),
 business_id uuid not null references public.businesses(id) on delete cascade,
 invoice_id uuid not null references public.subscription_invoices(id) on delete restrict,
 provider text not null check (provider in ('Orange Money','Afrimoney','Bank transfer','Cash / manual')),
 payment_reference text not null,
 amount numeric(12,2) not null check (amount > 0),
 currency_code text not null check (currency_code in ('SLE','USD')),
 status text not null default 'pending'
   check (status in ('pending','verified','rejected')),
 submitted_by uuid not null references auth.users(id),
 reviewed_by uuid references auth.users(id),
 review_notes text,
 submitted_at timestamptz not null default now(),
 reviewed_at timestamptz,
 unique (provider,payment_reference)
);

create table if not exists public.subscription_events (
 id bigint generated always as identity primary key,
 business_id uuid references public.businesses(id) on delete set null,
 invoice_id uuid references public.subscription_invoices(id) on delete set null,
 payment_id uuid references public.subscription_payments(id) on delete set null,
 actor_user_id uuid references auth.users(id) on delete set null,
 event_type text not null,
 details jsonb not null default '{}'::jsonb,
 created_at timestamptz not null default now()
);

create index if not exists subscription_invoices_business_created_idx
 on public.subscription_invoices(business_id,created_at desc);
create index if not exists subscription_payments_business_submitted_idx
 on public.subscription_payments(business_id,submitted_at desc);
create index if not exists subscription_payments_pending_idx
 on public.subscription_payments(status,submitted_at) where status='pending';

alter table public.subscription_plans enable row level security;
alter table public.business_subscriptions enable row level security;
alter table public.subscription_invoices enable row level security;
alter table public.subscription_payments enable row level security;
alter table public.subscription_events enable row level security;

drop policy if exists subscription_plans_read_active on public.subscription_plans;
create policy subscription_plans_read_active on public.subscription_plans
 for select to anon,authenticated using (is_active=true);

drop policy if exists business_subscriptions_read_admin on public.business_subscriptions;
create policy business_subscriptions_read_admin on public.business_subscriptions
 for select to authenticated using (
  public.has_business_role(business_id,array['owner','admin','accountant']::public.business_role[])
 );

drop policy if exists subscription_invoices_read_admin on public.subscription_invoices;
create policy subscription_invoices_read_admin on public.subscription_invoices
 for select to authenticated using (
  public.has_business_role(business_id,array['owner','admin','accountant']::public.business_role[])
 );

drop policy if exists subscription_payments_read_admin on public.subscription_payments;
create policy subscription_payments_read_admin on public.subscription_payments
 for select to authenticated using (
  public.has_business_role(business_id,array['owner','admin','accountant']::public.business_role[])
 );

drop policy if exists subscription_events_read_admin on public.subscription_events;
create policy subscription_events_read_admin on public.subscription_events
 for select to authenticated using (
  business_id is not null and public.has_business_role(business_id,array['owner','admin','accountant']::public.business_role[])
 );

revoke all on public.subscription_plans,public.business_subscriptions,public.subscription_invoices,
 public.subscription_payments,public.subscription_events from anon,authenticated;
grant select on public.subscription_plans to anon,authenticated;
grant select on public.business_subscriptions,public.subscription_invoices,
 public.subscription_payments,public.subscription_events to authenticated;

create or replace function public.request_business_subscription(
 p_business_id uuid,
 p_plan_code text,
 p_currency_code text,
 p_billing_cycle text
)
returns jsonb
language plpgsql
security definer
set search_path=''
as $$
declare
 v_plan public.subscription_plans%rowtype;
 v_amount numeric(12,2);
 v_subscription_id uuid;
 v_invoice_id uuid;
 v_invoice_number text;
begin
 if auth.uid() is null then raise exception 'Authentication required'; end if;
 if not public.has_business_role(p_business_id,array['owner','admin']::public.business_role[]) then
  raise exception 'Only the business owner or administrator can request a subscription';
 end if;
 if p_currency_code not in ('SLE','USD') then raise exception 'Choose SLE or USD'; end if;
 if p_billing_cycle not in ('monthly','annual') then raise exception 'Choose monthly or annual billing'; end if;
 select * into v_plan from public.subscription_plans where code=p_plan_code and is_active=true;
 if not found then raise exception 'The selected subscription plan is unavailable'; end if;
 v_amount:=case
  when p_currency_code='SLE' and p_billing_cycle='monthly' then v_plan.sle_monthly
  when p_currency_code='SLE' and p_billing_cycle='annual' then v_plan.sle_annual
  when p_currency_code='USD' and p_billing_cycle='monthly' then v_plan.usd_monthly
  else v_plan.usd_annual end;
 select id into v_subscription_id from public.business_subscriptions where business_id=p_business_id;
 insert into public.business_subscriptions(business_id,plan_code,status,currency_code,billing_cycle,updated_at)
 values(p_business_id,p_plan_code,'pending_payment',p_currency_code,p_billing_cycle,now())
 on conflict(business_id) do nothing
 returning id into v_subscription_id;
 if v_subscription_id is null then
  select id into v_subscription_id from public.business_subscriptions where business_id=p_business_id;
 end if;
 select id,invoice_number into v_invoice_id,v_invoice_number
 from public.subscription_invoices
 where business_id=p_business_id and status in ('pending','awaiting_verification')
 order by created_at desc limit 1;
 if v_invoice_id is not null then
  update public.subscription_invoices set status='void' where id=v_invoice_id;
 end if;
 v_invoice_number:='WL-'||to_char(now(),'YYYYMMDD')||'-'||upper(substr(replace(gen_random_uuid()::text,'-',''),1,8));
 insert into public.subscription_invoices(invoice_number,business_id,subscription_id,plan_code,currency_code,billing_cycle,amount_due,created_by)
 values(v_invoice_number,p_business_id,v_subscription_id,p_plan_code,p_currency_code,p_billing_cycle,v_amount,auth.uid())
 returning id into v_invoice_id;
 insert into public.subscription_events(business_id,invoice_id,actor_user_id,event_type,details)
 values(p_business_id,v_invoice_id,auth.uid(),'invoice_requested',
 jsonb_build_object('plan',p_plan_code,'currency',p_currency_code,'cycle',p_billing_cycle,'amount',v_amount));
 return jsonb_build_object('invoice_id',v_invoice_id,'invoice_number',v_invoice_number,
  'amount_due',v_amount,'currency_code',p_currency_code,'status','pending');
end;
$$;

create or replace function public.submit_subscription_payment(
 p_invoice_id uuid,
 p_provider text,
 p_payment_reference text,
 p_amount numeric
)
returns jsonb
language plpgsql
security definer
set search_path=''
as $$
declare
 v_invoice public.subscription_invoices%rowtype;
 v_payment_id uuid;
begin
 if auth.uid() is null then raise exception 'Authentication required'; end if;
 select * into v_invoice from public.subscription_invoices where id=p_invoice_id for update;
 if not found then raise exception 'Invoice not found'; end if;
 if not public.has_business_role(v_invoice.business_id,array['owner','admin']::public.business_role[]) then
  raise exception 'Only the business owner or administrator can submit payment';
 end if;
 if v_invoice.status not in ('pending','awaiting_verification') then raise exception 'This invoice is not awaiting payment'; end if;
 if p_provider not in ('Orange Money','Afrimoney','Bank transfer','Cash / manual') then raise exception 'Unsupported payment method'; end if;
 if length(trim(coalesce(p_payment_reference,'')))<3 then raise exception 'Enter the transaction reference or bank transfer details'; end if;
 if round(coalesce(p_amount,0),2)<>v_invoice.amount_due then raise exception 'Payment amount must exactly match the invoice total'; end if;
 insert into public.subscription_payments(business_id,invoice_id,provider,payment_reference,amount,currency_code,submitted_by)
 values(v_invoice.business_id,v_invoice.id,p_provider,trim(p_payment_reference),v_invoice.amount_due,v_invoice.currency_code,auth.uid())
 returning id into v_payment_id;
 update public.subscription_invoices set status='awaiting_verification' where id=v_invoice.id;
 insert into public.subscription_events(business_id,invoice_id,payment_id,actor_user_id,event_type,details)
 values(v_invoice.business_id,v_invoice.id,v_payment_id,auth.uid(),'payment_submitted',
 jsonb_build_object('provider',p_provider,'reference',trim(p_payment_reference),'amount',v_invoice.amount_due));
 return jsonb_build_object('payment_id',v_payment_id,'status','pending');
exception when unique_violation then
 raise exception 'This payment reference has already been submitted';
end;
$$;

create or replace function public.review_subscription_payment(
 p_payment_id uuid,
 p_approve boolean,
 p_notes text default ''
)
returns jsonb
language plpgsql
security definer
set search_path=''
as $$
declare
 v_payment public.subscription_payments%rowtype;
 v_invoice public.subscription_invoices%rowtype;
 v_subscription_id uuid;
 v_period_start timestamptz;
 v_period_end timestamptz;
 v_duration interval;
begin
 if auth.uid() is null or not public.is_platform_developer() then
  raise exception 'Platform Developer access required';
 end if;
 select * into v_payment from public.subscription_payments where id=p_payment_id for update;
 if not found then raise exception 'Payment submission not found'; end if;
 if v_payment.status<>'pending' then raise exception 'This payment has already been reviewed'; end if;
 select * into v_invoice from public.subscription_invoices where id=v_payment.invoice_id for update;
 if not found or v_invoice.status not in ('pending','awaiting_verification') then raise exception 'Invoice is no longer payable'; end if;
 if p_approve then
  if v_payment.amount<>v_invoice.amount_due or v_payment.currency_code<>v_invoice.currency_code then
   raise exception 'Payment amount or currency does not match the invoice';
  end if;
  v_duration:=case when v_invoice.billing_cycle='annual' then interval '1 year' else interval '1 month' end;
  select id into v_subscription_id from public.business_subscriptions where business_id=v_invoice.business_id for update;
  select greatest(coalesce(current_period_end,now()),now()) into v_period_start
   from public.business_subscriptions where id=v_subscription_id;
  v_period_start:=coalesce(v_period_start,now());
  v_period_end:=v_period_start+v_duration;
  update public.subscription_payments set status='verified',reviewed_by=auth.uid(),
   reviewed_at=now(),review_notes=nullif(trim(coalesce(p_notes,'')),'') where id=p_payment_id;
  update public.subscription_invoices set status='paid',paid_at=now() where id=v_invoice.id;
  update public.business_subscriptions set plan_code=v_invoice.plan_code,status='active',
   currency_code=v_invoice.currency_code,billing_cycle=v_invoice.billing_cycle,
   current_period_start=v_period_start,current_period_end=v_period_end,grace_until=null,
   cancel_at_period_end=false,updated_at=now() where id=v_subscription_id;
  insert into public.subscription_events(business_id,invoice_id,payment_id,actor_user_id,event_type,details)
  values(v_invoice.business_id,v_invoice.id,p_payment_id,auth.uid(),'payment_verified',
   jsonb_build_object('amount',v_payment.amount,'currency',v_payment.currency_code,'period_end',v_period_end,'notes',p_notes));
  return jsonb_build_object('success',true,'status','active','period_end',v_period_end);
 else
  update public.subscription_payments set status='rejected',reviewed_by=auth.uid(),
   reviewed_at=now(),review_notes=nullif(trim(coalesce(p_notes,'')),'') where id=p_payment_id;
  update public.subscription_invoices set status='pending' where id=v_invoice.id;
  insert into public.subscription_events(business_id,invoice_id,payment_id,actor_user_id,event_type,details)
  values(v_invoice.business_id,v_invoice.id,p_payment_id,auth.uid(),'payment_rejected',
   jsonb_build_object('notes',p_notes));
  return jsonb_build_object('success',true,'status','rejected');
 end if;
end;
$$;

create or replace function public.get_platform_billing_overview()
returns jsonb
language plpgsql
stable
security definer
set search_path=''
as $$
declare v_result jsonb;
begin
 if auth.uid() is null or not public.is_platform_developer() then
  raise exception 'Platform Developer access required';
 end if;
 select jsonb_build_object(
  'active_subscriptions',(select count(*) from public.business_subscriptions where status='active'),
  'pending_payments',(select count(*) from public.subscription_payments where status='pending'),
  'pending_invoices',(select count(*) from public.subscription_invoices where status in ('pending','awaiting_verification')),
  'paid_sle',(select coalesce(sum(amount),0) from public.subscription_payments where status='verified' and currency_code='SLE'),
  'paid_usd',(select coalesce(sum(amount),0) from public.subscription_payments where status='verified' and currency_code='USD'),
  'plans',(select coalesce(jsonb_agg(jsonb_build_object('code',p.code,'name',p.name,'active_count',coalesce(x.cnt,0)) order by p.display_order),'[]'::jsonb)
    from public.subscription_plans p left join
     (select plan_code,count(*) cnt from public.business_subscriptions where status='active' group by plan_code) x
     on x.plan_code=p.code),
  'pending',(select coalesce(jsonb_agg(jsonb_build_object(
    'payment_id',sp.id,'business_id',sp.business_id,'business_name',b.name,
    'invoice_number',si.invoice_number,'plan_code',si.plan_code,'provider',sp.provider,
    'reference',sp.payment_reference,'amount',sp.amount,'currency_code',sp.currency_code,
    'submitted_at',sp.submitted_at
   ) order by sp.submitted_at),'[]'::jsonb)
   from public.subscription_payments sp
   join public.subscription_invoices si on si.id=sp.invoice_id
   join public.businesses b on b.id=sp.business_id
   where sp.status='pending')
 ) into v_result;
 return v_result;
end;
$$;

revoke all on function public.request_business_subscription(uuid,text,text,text) from public,anon;
revoke all on function public.submit_subscription_payment(uuid,text,text,numeric) from public,anon;
revoke all on function public.review_subscription_payment(uuid,boolean,text) from public,anon;
revoke all on function public.get_platform_billing_overview() from public,anon;
grant execute on function public.request_business_subscription(uuid,text,text,text) to authenticated;
grant execute on function public.submit_subscription_payment(uuid,text,text,numeric) to authenticated;
grant execute on function public.review_subscription_payment(uuid,boolean,text) to authenticated;
grant execute on function public.get_platform_billing_overview() to authenticated;

commit;
