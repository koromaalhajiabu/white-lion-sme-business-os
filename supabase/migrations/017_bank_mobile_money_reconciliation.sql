-- White Lion SME Business OS — Migration 017
-- Bank and mobile-money statement import and cashbook reconciliation.
-- CSV statements are imported by an authorised finance user; no bank API is implied.
begin;

create table if not exists public.bank_accounts (
  id uuid primary key default gen_random_uuid(),
  business_id uuid not null references public.businesses(id) on delete cascade,
  branch_id uuid,
  account_name text not null check (length(trim(account_name)) between 2 and 100),
  institution_name text not null check (length(trim(institution_name)) between 2 and 120),
  account_type text not null default 'bank' check (account_type in ('bank','mobile_money','cash_clearing','other')),
  account_last4 text check (account_last4 is null or account_last4 ~ '^[0-9]{4}$'),
  currency text not null default 'SLE' check (currency ~ '^[A-Z]{3}$'),
  opening_balance numeric(14,2) not null default 0,
  is_active boolean not null default true,
  created_by uuid default auth.uid() references auth.users(id) on delete set null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique(id,business_id),
  foreign key(branch_id,business_id) references public.branches(id,business_id) on delete set null (branch_id)
);

create unique index if not exists cashbook_entries_id_business_uidx
  on public.cashbook_entries(id,business_id);

alter table public.cashbook_entries
  add column if not exists bank_account_id uuid;
create index if not exists cashbook_bank_account_date_idx
  on public.cashbook_entries(business_id,bank_account_id,entry_date desc);

do $$
begin
  if not exists (select 1 from pg_constraint where conname='cashbook_bank_account_business_fk') then
    alter table public.cashbook_entries
      add constraint cashbook_bank_account_business_fk
      foreign key(bank_account_id,business_id)
      references public.bank_accounts(id,business_id) on delete restrict;
  end if;
end $$;

create table if not exists public.bank_statement_lines (
  id uuid primary key default gen_random_uuid(),
  business_id uuid not null,
  bank_account_id uuid not null,
  transaction_date date not null,
  description text not null check (length(trim(description)) between 1 and 500),
  reference text,
  amount numeric(14,2) not null check (amount > 0),
  direction text not null check (direction in ('debit','credit')),
  status text not null default 'unmatched' check (status in ('unmatched','matched','ignored')),
  matched_cashbook_entry_id uuid,
  matched_by uuid references auth.users(id) on delete set null,
  matched_at timestamptz,
  imported_by uuid default auth.uid() references auth.users(id) on delete set null,
  imported_at timestamptz not null default now(),
  foreign key(bank_account_id,business_id) references public.bank_accounts(id,business_id) on delete cascade,
  foreign key(matched_cashbook_entry_id,business_id) references public.cashbook_entries(id,business_id) on delete restrict,
  unique(id,business_id)
);

create unique index if not exists bank_statement_external_ref_uidx
  on public.bank_statement_lines(bank_account_id,reference)
  where reference is not null and reference <> '';
create unique index if not exists bank_statement_cashbook_match_uidx
  on public.bank_statement_lines(matched_cashbook_entry_id)
  where matched_cashbook_entry_id is not null;
create index if not exists bank_statement_reconcile_idx
  on public.bank_statement_lines(business_id,bank_account_id,transaction_date,status);
create index if not exists bank_accounts_business_idx
  on public.bank_accounts(business_id,is_active);

alter table public.bank_accounts enable row level security;
alter table public.bank_statement_lines enable row level security;

drop policy if exists bank_accounts_finance_read on public.bank_accounts;
create policy bank_accounts_finance_read on public.bank_accounts
for select to authenticated
using (public.has_business_role(business_id,array['owner','admin','manager','accountant']::public.business_role[]));

drop policy if exists bank_accounts_finance_manage on public.bank_accounts;
create policy bank_accounts_finance_manage on public.bank_accounts
for all to authenticated
using (public.has_business_role(business_id,array['owner','admin','accountant']::public.business_role[]))
with check (public.has_business_role(business_id,array['owner','admin','accountant']::public.business_role[]));

drop policy if exists bank_statement_finance_read on public.bank_statement_lines;
create policy bank_statement_finance_read on public.bank_statement_lines
for select to authenticated
using (public.has_business_role(business_id,array['owner','admin','manager','accountant']::public.business_role[]));

-- Statement lines are written only through the validated import/match RPCs.
drop policy if exists bank_statement_no_direct_write on public.bank_statement_lines;
create policy bank_statement_no_direct_write on public.bank_statement_lines
for all to authenticated using(false) with check(false);

revoke all on public.bank_accounts,public.bank_statement_lines from anon,public,authenticated;
grant select,insert,update,delete on public.bank_accounts to authenticated;
grant select on public.bank_statement_lines to authenticated;

create or replace function public.import_bank_statement_lines(
  p_bank_account_id uuid,
  p_lines jsonb
) returns jsonb
language plpgsql
security definer
set search_path=''
as $$
declare
  v_business_id uuid;
  v_count integer := 0;
begin
  if auth.uid() is null then raise exception 'Authentication required'; end if;
  select business_id into v_business_id
  from public.bank_accounts
  where id=p_bank_account_id and is_active
  for update;
  if not found then raise exception 'Active bank or mobile-money account not found'; end if;
  if not public.has_business_role(v_business_id,array['owner','admin','accountant']::public.business_role[]) then
    raise exception 'Only an owner, administrator or accountant can import statements';
  end if;
  if p_lines is null then raise exception 'Statement rows are required'; end if;
  if jsonb_typeof(p_lines)<>'array' then raise exception 'Statement rows must be a JSON array'; end if;
  if jsonb_array_length(p_lines)=0 or jsonb_array_length(p_lines)>5000 then
    raise exception 'Provide between 1 and 5000 statement rows';
  end if;
  if exists (
    select 1
    from jsonb_to_recordset(p_lines) as x(transaction_date date,description text,reference text,amount numeric,direction text)
    where x.transaction_date is null
       or length(trim(coalesce(x.description,'')))=0
       or x.amount is null or x.amount<=0
       or x.direction is null or x.direction not in ('debit','credit')
  ) then raise exception 'Every row needs a date, description, positive amount and debit/credit direction'; end if;

  insert into public.bank_statement_lines(
    business_id,bank_account_id,transaction_date,description,reference,amount,direction,imported_by
  )
  select v_business_id,p_bank_account_id,x.transaction_date,trim(x.description),
         nullif(trim(coalesce(x.reference,'')),''),x.amount,x.direction,auth.uid()
  from jsonb_to_recordset(p_lines) as x(
    transaction_date date,description text,reference text,amount numeric,direction text
  )
  on conflict (bank_account_id,reference)
    where reference is not null and reference<>''
    do nothing;
  get diagnostics v_count = row_count;
  insert into public.audit_logs(business_id,actor_user_id,action,entity_table,entity_id,details)
  values(v_business_id,auth.uid(),'bank_statement_imported','bank_statement_lines',p_bank_account_id::text,
    jsonb_build_object('bank_account_id',p_bank_account_id,'inserted_rows',v_count));
  return jsonb_build_object('status','imported','inserted_rows',v_count);
end;
$$;

create or replace function public.match_bank_statement_line(
  p_statement_line_id uuid,
  p_cashbook_entry_id uuid
) returns jsonb
language plpgsql
security definer
set search_path=''
as $$
declare
  v_line public.bank_statement_lines%rowtype;
  v_cash public.cashbook_entries%rowtype;
begin
  if auth.uid() is null then raise exception 'Authentication required'; end if;
  select * into v_line from public.bank_statement_lines
  where id=p_statement_line_id for update;
  if not found then raise exception 'Statement line not found'; end if;
  if not public.has_business_role(v_line.business_id,array['owner','admin','accountant']::public.business_role[]) then
    raise exception 'Only an owner, administrator or accountant can reconcile statements';
  end if;
  select * into v_cash from public.cashbook_entries
  where id=p_cashbook_entry_id and business_id=v_line.business_id for update;
  if not found then raise exception 'Matching cashbook entry not found in this business'; end if;
  if v_line.status<>'unmatched' then raise exception 'This statement line is not unmatched'; end if;
  if v_cash.bank_account_id is distinct from v_line.bank_account_id then
    raise exception 'The cashbook entry must belong to the same bank or mobile-money account';
  end if;
  if abs(v_cash.amount-v_line.amount)>0.01 then
    raise exception 'Amounts do not match; review the entries before reconciling';
  end if;
  if (v_line.direction='credit' and v_cash.entry_type<>'income')
     or (v_line.direction='debit' and v_cash.entry_type<>'expense') then
    raise exception 'Statement direction does not match the cashbook entry';
  end if;
  update public.bank_statement_lines
  set status='matched',matched_cashbook_entry_id=v_cash.id,matched_by=auth.uid(),matched_at=now()
  where id=v_line.id;
  insert into public.audit_logs(business_id,actor_user_id,action,entity_table,entity_id,details)
  values(v_line.business_id,auth.uid(),'bank_statement_line_matched','bank_statement_lines',v_line.id::text,
    jsonb_build_object('cashbook_entry_id',v_cash.id,'bank_account_id',v_line.bank_account_id,'amount',v_line.amount));
  return jsonb_build_object('status','matched','statement_line_id',v_line.id,'cashbook_entry_id',v_cash.id);
end;
$$;

revoke all on function public.import_bank_statement_lines(uuid,jsonb) from public;
revoke all on function public.match_bank_statement_line(uuid,uuid) from public;
grant execute on function public.import_bank_statement_lines(uuid,jsonb) to authenticated;
grant execute on function public.match_bank_statement_line(uuid,uuid) to authenticated;

commit;
