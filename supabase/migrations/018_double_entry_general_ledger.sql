-- White Lion SME Business OS — Migration 018
-- Double-entry general ledger, automated source posting and financial reports.
-- Existing operational records are preserved. Triggers post new source records only.
begin;

create table if not exists public.chart_of_accounts (
  id uuid primary key default gen_random_uuid(),
  business_id uuid not null references public.businesses(id) on delete cascade,
  account_code text not null check (account_code ~ '^[0-9]{4,6}$'),
  account_name text not null check (length(trim(account_name)) between 2 and 120),
  account_type text not null check (account_type in ('asset','liability','equity','income','expense')),
  normal_balance text not null check (normal_balance in ('debit','credit')),
  is_system boolean not null default false,
  is_active boolean not null default true,
  created_at timestamptz not null default now(),
  unique (business_id,account_code),
  unique (id,business_id)
);

create table if not exists public.journal_entries (
  id uuid primary key default gen_random_uuid(),
  business_id uuid not null references public.businesses(id) on delete cascade,
  entry_number bigint generated always as identity,
  journal_date date not null default current_date,
  memo text not null check (length(trim(memo)) between 2 and 500),
  source_type text not null default 'manual',
  source_id text,
  status text not null default 'draft' check (status in ('draft','posted')),
  created_by uuid references auth.users(id) on delete set null default auth.uid(),
  posted_by uuid references auth.users(id) on delete set null,
  posted_at timestamptz,
  created_at timestamptz not null default now(),
  unique (id,business_id),
  unique (business_id,source_type,source_id),
  check ((status='draft' and posted_at is null) or (status='posted' and posted_at is not null))
);

create table if not exists public.journal_lines (
  id uuid primary key default gen_random_uuid(),
  business_id uuid not null,
  journal_entry_id uuid not null,
  account_id uuid not null,
  description text,
  debit numeric(18,2) not null default 0 check (debit >= 0),
  credit numeric(18,2) not null default 0 check (credit >= 0),
  created_at timestamptz not null default now(),
  foreign key (journal_entry_id,business_id)
    references public.journal_entries(id,business_id) on delete restrict,
  foreign key (account_id,business_id)
    references public.chart_of_accounts(id,business_id) on delete restrict,
  check ((debit > 0 and credit = 0) or (credit > 0 and debit = 0))
);

create index if not exists chart_accounts_business_type_idx
  on public.chart_of_accounts(business_id,account_type,account_code);
create index if not exists journal_entries_business_date_idx
  on public.journal_entries(business_id,journal_date desc,status);
create index if not exists journal_lines_business_account_idx
  on public.journal_lines(business_id,account_id,journal_entry_id);

alter table public.chart_of_accounts enable row level security;
alter table public.journal_entries enable row level security;
alter table public.journal_lines enable row level security;

drop policy if exists chart_accounts_member_read on public.chart_of_accounts;
create policy chart_accounts_member_read on public.chart_of_accounts
for select to authenticated using (public.is_business_member(business_id));
drop policy if exists journal_entries_finance_read on public.journal_entries;
create policy journal_entries_finance_read on public.journal_entries
for select to authenticated using (
  public.has_business_role(business_id,array['owner','admin','manager','accountant']::public.business_role[])
);
drop policy if exists journal_lines_finance_read on public.journal_lines;
create policy journal_lines_finance_read on public.journal_lines
for select to authenticated using (
  public.has_business_role(business_id,array['owner','admin','manager','accountant']::public.business_role[])
);

revoke all on public.chart_of_accounts,public.journal_entries,public.journal_lines from anon,public,authenticated;
grant select on public.chart_of_accounts,public.journal_entries,public.journal_lines to authenticated;

create or replace function public.seed_default_chart_of_accounts(p_business_id uuid)
returns void language plpgsql security definer set search_path=''
as $$
begin
  insert into public.chart_of_accounts(business_id,account_code,account_name,account_type,normal_balance,is_system)
  values
    (p_business_id,'1000','Cash and bank','asset','debit',true),
    (p_business_id,'1100','Accounts receivable','asset','debit',true),
    (p_business_id,'1200','Inventory','asset','debit',true),
    (p_business_id,'1500','Property and equipment','asset','debit',true),
    (p_business_id,'2000','Accounts payable','liability','credit',true),
    (p_business_id,'2100','Other liabilities','liability','credit',true),
    (p_business_id,'3000','Owner capital','equity','credit',true),
    (p_business_id,'3200','Retained earnings','equity','credit',true),
    (p_business_id,'4000','Sales revenue','income','credit',true),
    (p_business_id,'4050','Sales returns and allowances','income','debit',true),
    (p_business_id,'4100','Other operating income','income','credit',true),
    (p_business_id,'5000','Cost of goods sold','expense','debit',true),
    (p_business_id,'6000','Operating expenses','expense','debit',true),
    (p_business_id,'6100','Bank and payment charges','expense','debit',true)
  on conflict (business_id,account_code) do nothing;
end;
$$;

create or replace function public.accounting_business_created()
returns trigger language plpgsql security definer set search_path=''
as $$
begin
  perform public.seed_default_chart_of_accounts(new.id);
  return new;
end;
$$;
drop trigger if exists trg_accounting_seed_business on public.businesses;
create trigger trg_accounting_seed_business after insert on public.businesses
for each row execute function public.accounting_business_created();

-- Seed charts for businesses that existed before this migration.
do $$
declare r record;
begin
  for r in select id from public.businesses loop
    perform public.seed_default_chart_of_accounts(r.id);
  end loop;
end;
$$;

create or replace function public.initialize_accounting(p_business_id uuid)
returns jsonb language plpgsql security definer set search_path=''
as $$
begin
  if auth.uid() is null or not public.has_business_role(
    p_business_id,array['owner','admin','accountant']::public.business_role[]
  ) then raise exception 'Only an owner, administrator or accountant can initialise accounting'; end if;
  perform public.seed_default_chart_of_accounts(p_business_id);
  return jsonb_build_object('status','ready','account_count',
    (select count(*) from public.chart_of_accounts where business_id=p_business_id));
end;
$$;

-- Internal posting routine. The source record and journal are committed atomically.
create or replace function public.post_system_journal(
  p_business_id uuid,p_journal_date date,p_memo text,p_source_type text,p_source_id text,p_lines jsonb
) returns uuid language plpgsql security definer set search_path=''
as $$
declare
  v_journal_id uuid;
  v_debits numeric(18,2);
  v_credits numeric(18,2);
  v_count integer;
  v_missing integer;
begin
  perform public.seed_default_chart_of_accounts(p_business_id);
  if jsonb_typeof(p_lines)<>'array' or jsonb_array_length(p_lines)<2 then
    raise exception 'A journal must contain at least two lines';
  end if;
  select count(*),coalesce(sum(x.debit),0),coalesce(sum(x.credit),0)
  into v_count,v_debits,v_credits
  from jsonb_to_recordset(p_lines) as x(code text,debit numeric,credit numeric);
  if v_count<2 or v_debits<=0 or abs(v_debits-v_credits)>0.005 then
    raise exception 'Journal is not balanced: debits % and credits %',v_debits,v_credits;
  end if;
  if exists(select 1 from jsonb_to_recordset(p_lines) as x(code text,debit numeric,credit numeric)
    where x.code is null or (coalesce(x.debit,0)>0 and coalesce(x.credit,0)>0)
      or coalesce(x.debit,0)<0 or coalesce(x.credit,0)<0
      or (coalesce(x.debit,0)=0 and coalesce(x.credit,0)=0)) then
    raise exception 'Each journal line must contain either a positive debit or a positive credit';
  end if;
  select count(*) into v_missing
  from jsonb_to_recordset(p_lines) as x(code text,debit numeric,credit numeric)
  left join public.chart_of_accounts a
    on a.business_id=p_business_id and a.account_code=x.code and a.is_active
  where a.id is null;
  if v_missing>0 then raise exception 'One or more account codes are missing or inactive'; end if;

  insert into public.journal_entries(business_id,journal_date,memo,source_type,source_id,status)
  values(p_business_id,coalesce(p_journal_date,current_date),trim(p_memo),p_source_type,p_source_id,'draft')
  returning id into v_journal_id;

  insert into public.journal_lines(business_id,journal_entry_id,account_id,description,debit,credit)
  select p_business_id,v_journal_id,a.id,x.description,coalesce(x.debit,0),coalesce(x.credit,0)
  from jsonb_to_recordset(p_lines) as x(code text,debit numeric,credit numeric,description text)
  join public.chart_of_accounts a
    on a.business_id=p_business_id and a.account_code=x.code and a.is_active;

  update public.journal_entries
  set status='posted',posted_at=now(),posted_by=auth.uid()
  where id=v_journal_id;
  insert into public.audit_logs(business_id,actor_user_id,action,entity_table,entity_id,details)
  values(p_business_id,auth.uid(),'journal_posted','journal_entries',v_journal_id::text,
    jsonb_build_object('source_type',p_source_type,'source_id',p_source_id,'debits',v_debits,'credits',v_credits));
  return v_journal_id;
end;
$$;

create or replace function public.post_general_journal(
  p_business_id uuid,p_journal_date date,p_memo text,p_lines jsonb
) returns uuid language plpgsql security definer set search_path=''
as $$
begin
  if auth.uid() is null or not public.has_business_role(
    p_business_id,array['owner','admin','accountant']::public.business_role[]
  ) then raise exception 'Only an owner, administrator or accountant can post manual journals'; end if;
  return public.post_system_journal(p_business_id,p_journal_date,p_memo,'manual',null,p_lines);
end;
$$;

-- Posted journals and their lines are immutable. Corrections require a new reversing journal.
create or replace function public.protect_posted_journal()
returns trigger language plpgsql set search_path=''
as $$
declare v_status text;
begin
  if tg_table_name='journal_entries' then
    if old.status='posted' then raise exception 'Posted journals are immutable; post a reversing journal instead'; end if;
    if tg_op='DELETE' then return old; end if;
    return new;
  end if;
  select status into v_status from public.journal_entries
  where id=coalesce(old.journal_entry_id,new.journal_entry_id)
    and business_id=coalesce(old.business_id,new.business_id);
  if v_status='posted' then raise exception 'Lines in a posted journal are immutable'; end if;
  if tg_op='DELETE' then return old; end if;
  return new;
end;
$$;
drop trigger if exists trg_protect_posted_journal on public.journal_entries;
create trigger trg_protect_posted_journal before update or delete on public.journal_entries
for each row execute function public.protect_posted_journal();
drop trigger if exists trg_protect_posted_journal_lines on public.journal_lines;
create trigger trg_protect_posted_journal_lines before update or delete on public.journal_lines
for each row execute function public.protect_posted_journal();

-- Automatic accounting: new cloud-synced sales and purchases.
create or replace function public.account_for_offline_sale()
returns trigger language plpgsql security definer set search_path=''
as $$
declare v_cogs numeric(18,2); v_lines jsonb;
begin
  v_cogs:=0; -- Historical cost layers are not yet tracked; do not invent COGS.
  v_lines=jsonb_build_array(
    jsonb_build_object('code',case when lower(coalesce(new.payment_method,'')) in ('credit','on credit','accounts receivable') then '1100' else '1000' end,'debit',new.total,'credit',0,'description','Sale proceeds'),
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
drop trigger if exists trg_account_for_offline_sale on public.offline_sales;
drop trigger if exists trg_account_for_offline_sale on public.offline_sales;
create constraint trigger trg_account_for_offline_sale after insert on public.offline_sales
 deferrable initially deferred for each row execute function public.account_for_offline_sale();

create or replace function public.account_for_offline_purchase()
returns trigger language plpgsql security definer set search_path=''
as $$
begin
  perform public.post_system_journal(new.business_id,new.transaction_date,
    'Purchase transaction · '||coalesce(new.supplier_name,'Supplier'),
    'offline_purchase',new.id::text,jsonb_build_array(
      jsonb_build_object('code','1200','debit',new.total,'credit',0,'description','Inventory purchased'),
      jsonb_build_object('code','2000','debit',0,'credit',new.total,'description','Supplier payable')
    ));
  return new;
end;
$$;
drop trigger if exists trg_account_for_offline_purchase on public.offline_purchases;
create trigger trg_account_for_offline_purchase after insert on public.offline_purchases
for each row execute function public.account_for_offline_purchase();

create or replace function public.account_for_expense()
returns trigger language plpgsql security definer set search_path=''
as $$
begin
  perform public.post_system_journal(new.business_id,new.expense_date,
    'Expense · '||new.category||' · '||new.description,'expense',new.id::text,jsonb_build_array(
      jsonb_build_object('code','6000','debit',new.amount,'credit',0,'description',new.category),
      jsonb_build_object('code','1000','debit',0,'credit',new.amount,'description','Cash / bank paid')
    ));
  return new;
end;
$$;
drop trigger if exists trg_account_for_expense on public.expenses;
create trigger trg_account_for_expense after insert on public.expenses
for each row execute function public.account_for_expense();

create or replace function public.account_for_sale_return()
returns trigger language plpgsql security definer set search_path=''
as $$
begin
  if new.refund_total>0 then
    perform public.post_system_journal(new.business_id,new.created_at::date,
      'Sales return · '||new.reason,'sale_return',new.id::text,jsonb_build_array(
        jsonb_build_object('code','4050','debit',new.refund_total,'credit',0,'description','Sales returns'),
        jsonb_build_object('code','1000','debit',0,'credit',new.refund_total,'description','Refund paid')
      ));
  end if;
  return new;
end;
$$;
drop trigger if exists trg_account_for_sale_return on public.offline_sale_returns;
create trigger trg_account_for_sale_return after insert on public.offline_sale_returns
for each row execute function public.account_for_sale_return();

create or replace function public.account_for_obligation_payment()
returns trigger language plpgsql security definer set search_path=''
as $$
declare v_type text; v_party text;
begin
  select obligation_type,party_name into v_type,v_party
  from public.financial_obligations where id=new.obligation_id and business_id=new.business_id;
  if v_type='receivable' then
    perform public.post_system_journal(new.business_id,new.payment_date,
      'Receivable collected · '||v_party,'obligation_payment',new.id::text,jsonb_build_array(
        jsonb_build_object('code','1000','debit',new.amount,'credit',0,'description','Cash received'),
        jsonb_build_object('code','1100','debit',0,'credit',new.amount,'description','Accounts receivable settled')
      ));
  elsif v_type='payable' then
    perform public.post_system_journal(new.business_id,new.payment_date,
      'Supplier payment · '||v_party,'obligation_payment',new.id::text,jsonb_build_array(
        jsonb_build_object('code','2000','debit',new.amount,'credit',0,'description','Accounts payable settled'),
        jsonb_build_object('code','1000','debit',0,'credit',new.amount,'description','Cash paid')
      ));
  end if;
  return new;
end;
$$;
drop trigger if exists trg_account_for_obligation_payment on public.financial_obligation_payments;
create trigger trg_account_for_obligation_payment after insert on public.financial_obligation_payments
for each row execute function public.account_for_obligation_payment();

-- Reporting functions return only the requesting member's authorised business data.
create or replace function public.accounting_trial_balance(
  p_business_id uuid,p_from date default null,p_to date default current_date
) returns table(account_code text,account_name text,account_type text,total_debit numeric,total_credit numeric,net_balance numeric)
language plpgsql security definer set search_path=''
as $$
begin
  if auth.uid() is null or not public.has_business_role(
    p_business_id,array['owner','admin','manager','accountant']::public.business_role[]
  ) then raise exception 'Not authorised to view accounting reports'; end if;
  return query
  select a.account_code,a.account_name,a.account_type,
    coalesce(sum(l.debit),0)::numeric,coalesce(sum(l.credit),0)::numeric,
    case when a.normal_balance='debit' then coalesce(sum(l.debit-l.credit),0)
         else coalesce(sum(l.credit-l.debit),0) end::numeric
  from public.chart_of_accounts a
  left join public.journal_lines l on l.account_id=a.id and l.business_id=a.business_id
  left join public.journal_entries j on j.id=l.journal_entry_id and j.business_id=l.business_id
    and j.status='posted' and j.journal_date<=coalesce(p_to,current_date)
    and (p_from is null or j.journal_date>=p_from)
  where a.business_id=p_business_id and a.is_active
  group by a.id,a.account_code,a.account_name,a.account_type,a.normal_balance
  order by a.account_code;
end;
$$;

create or replace function public.accounting_income_statement(
  p_business_id uuid,p_from date default date_trunc('month',current_date)::date,p_to date default current_date
) returns table(account_code text,account_name text,account_type text,amount numeric)
language plpgsql security definer set search_path=''
as $$
begin
  if auth.uid() is null or not public.has_business_role(
    p_business_id,array['owner','admin','manager','accountant']::public.business_role[]
  ) then raise exception 'Not authorised to view accounting reports'; end if;
  return query
  select a.account_code,a.account_name,a.account_type,
    case when a.account_type='income' then coalesce(sum(l.credit-l.debit),0)
         else coalesce(sum(l.debit-l.credit),0) end::numeric
  from public.chart_of_accounts a
  left join public.journal_lines l on l.account_id=a.id and l.business_id=a.business_id
  left join public.journal_entries j on j.id=l.journal_entry_id and j.business_id=l.business_id
    and j.status='posted' and j.journal_date between coalesce(p_from,'0001-01-01') and coalesce(p_to,current_date)
  where a.business_id=p_business_id and a.is_active and a.account_type in ('income','expense')
  group by a.id,a.account_code,a.account_name,a.account_type
  order by a.account_code;
end;
$$;

create or replace function public.accounting_balance_sheet(
  p_business_id uuid,p_as_of date default current_date
) returns table(account_code text,account_name text,account_type text,amount numeric)
language plpgsql security definer set search_path=''
as $$
begin
  if auth.uid() is null or not public.has_business_role(
    p_business_id,array['owner','admin','manager','accountant']::public.business_role[]
  ) then raise exception 'Not authorised to view accounting reports'; end if;
  return query
  select a.account_code,a.account_name,a.account_type,
    case when a.normal_balance='debit' then coalesce(sum(l.debit-l.credit),0)
         else coalesce(sum(l.credit-l.debit),0) end::numeric
  from public.chart_of_accounts a
  left join public.journal_lines l on l.account_id=a.id and l.business_id=a.business_id
  left join public.journal_entries j on j.id=l.journal_entry_id and j.business_id=l.business_id
    and j.status='posted' and j.journal_date<=coalesce(p_as_of,current_date)
  where a.business_id=p_business_id and a.is_active
    and a.account_type in ('asset','liability','equity')
  group by a.id,a.account_code,a.account_name,a.account_type,a.normal_balance
  union all
  select '3999'::text,'Accumulated earnings (unclosed)'::text,'equity'::text,
    coalesce(sum(case when a.account_type='income' then l.credit-l.debit
                      else l.debit-l.credit end),0)::numeric
  from public.chart_of_accounts a
  join public.journal_lines l on l.account_id=a.id and l.business_id=a.business_id
  join public.journal_entries j on j.id=l.journal_entry_id and j.business_id=l.business_id
  where a.business_id=p_business_id and a.account_type in ('income','expense')
    and j.status='posted' and j.journal_date<=coalesce(p_as_of,current_date)
  order by 3,1;
end;
$$;
create or replace function public.accounting_cash_flow(
  p_business_id uuid,p_from date default date_trunc('month',current_date)::date,p_to date default current_date
) returns table(account_name text,cash_in numeric,cash_out numeric,net_cash_flow numeric)
language plpgsql security definer set search_path=''
as $$
begin
  if auth.uid() is null or not public.has_business_role(
    p_business_id,array['owner','admin','manager','accountant']::public.business_role[]
  ) then raise exception 'Not authorised to view accounting reports'; end if;
  return query
  select a.account_name,coalesce(sum(l.debit),0)::numeric,coalesce(sum(l.credit),0)::numeric,
    coalesce(sum(l.debit-l.credit),0)::numeric
  from public.chart_of_accounts a
  join public.journal_lines l on l.account_id=a.id and l.business_id=a.business_id
  join public.journal_entries j on j.id=l.journal_entry_id and j.business_id=l.business_id
  where a.business_id=p_business_id and a.account_code='1000' and j.status='posted'
    and j.journal_date between coalesce(p_from,'0001-01-01') and coalesce(p_to,current_date)
  group by a.id,a.account_name;
end;
$$;

revoke all on function public.seed_default_chart_of_accounts(uuid) from public;
revoke all on function public.accounting_business_created() from public;
revoke all on function public.post_system_journal(uuid,date,text,text,text,jsonb) from public;
revoke all on function public.protect_posted_journal() from public;
revoke all on function public.account_for_offline_sale() from public;
revoke all on function public.account_for_offline_purchase() from public;
revoke all on function public.account_for_expense() from public;
revoke all on function public.account_for_sale_return() from public;
revoke all on function public.account_for_obligation_payment() from public;
revoke all on function public.initialize_accounting(uuid) from public;
revoke all on function public.post_general_journal(uuid,date,text,jsonb) from public;
revoke all on function public.accounting_trial_balance(uuid,date,date) from public;
revoke all on function public.accounting_income_statement(uuid,date,date) from public;
revoke all on function public.accounting_balance_sheet(uuid,date) from public;
revoke all on function public.accounting_cash_flow(uuid,date,date) from public;

grant execute on function public.initialize_accounting(uuid) to authenticated;
grant execute on function public.post_general_journal(uuid,date,text,jsonb) to authenticated;
grant execute on function public.accounting_trial_balance(uuid,date,date) to authenticated;
grant execute on function public.accounting_income_statement(uuid,date,date) to authenticated;
grant execute on function public.accounting_balance_sheet(uuid,date) to authenticated;
grant execute on function public.accounting_cash_flow(uuid,date,date) to authenticated;

commit;
