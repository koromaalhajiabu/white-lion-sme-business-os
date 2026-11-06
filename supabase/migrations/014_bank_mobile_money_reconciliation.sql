-- White Lion SME Business OS — Migration 014
-- Bank and mobile-money statement imports and reconciliation.
begin;

create table if not exists public.statement_imports (
  id uuid primary key default gen_random_uuid(),
  business_id uuid not null references public.businesses(id) on delete cascade,
  branch_id uuid null,
  account_type text not null check (account_type in ('bank','mobile_money')),
  account_name text not null,
  file_name text not null,
  file_hash text not null,
  statement_start date null,
  statement_end date null,
  row_count integer not null default 0 check (row_count >= 0),
  imported_count integer not null default 0 check (imported_count >= 0),
  duplicate_count integer not null default 0 check (duplicate_count >= 0),
  imported_by uuid null default auth.uid() references auth.users(id) on delete set null,
  created_at timestamptz not null default now(),
  constraint statement_import_branch_business_fk foreign key(branch_id,business_id)
    references public.branches(id,business_id) on delete set null (branch_id),
  constraint statement_import_file_unique unique (business_id,account_name,file_hash)
);

create table if not exists public.statement_transactions (
  id uuid primary key default gen_random_uuid(),
  business_id uuid not null references public.businesses(id) on delete cascade,
  import_id uuid not null references public.statement_imports(id) on delete cascade,
  account_name text not null,
  transaction_date date not null,
  description text not null,
  reference text null,
  direction text not null check (direction in ('in','out')),
  amount numeric(14,2) not null check (amount > 0),
  running_balance numeric(14,2) null,
  fingerprint text not null,
  status text not null default 'unmatched' check (status in ('unmatched','matched','ignored')),
  cashbook_entry_id uuid null references public.cashbook_entries(id) on delete restrict,
  matched_by uuid null references auth.users(id) on delete set null,
  matched_at timestamptz null,
  created_at timestamptz not null default now(),
  constraint statement_transaction_fingerprint_unique unique (business_id,account_name,fingerprint),
  constraint statement_transaction_match_state check (
    (status = 'matched' and cashbook_entry_id is not null)
    or (status <> 'matched' and cashbook_entry_id is null)
  )
);

create index if not exists statement_imports_business_created_idx
  on public.statement_imports(business_id,created_at desc);
create index if not exists statement_transactions_business_date_idx
  on public.statement_transactions(business_id,transaction_date desc);
create index if not exists statement_transactions_import_idx
  on public.statement_transactions(import_id);
create index if not exists statement_transactions_cashbook_idx
  on public.statement_transactions(cashbook_entry_id);

alter table public.statement_imports enable row level security;
alter table public.statement_transactions enable row level security;

drop policy if exists statement_imports_member_read on public.statement_imports;
create policy statement_imports_member_read on public.statement_imports
  for select to authenticated
  using (public.is_business_member(business_id));

drop policy if exists statement_imports_finance_insert on public.statement_imports;
create policy statement_imports_finance_insert on public.statement_imports
  for insert to authenticated
  with check (public.has_business_role(business_id,array['owner','admin','manager','accountant']::public.business_role[]));

drop policy if exists statement_imports_finance_delete on public.statement_imports;
create policy statement_imports_finance_delete on public.statement_imports
  for delete to authenticated
  using (public.has_business_role(business_id,array['owner','admin','manager','accountant']::public.business_role[]));

drop policy if exists statement_transactions_member_read on public.statement_transactions;
create policy statement_transactions_member_read on public.statement_transactions
  for select to authenticated
  using (public.is_business_member(business_id));

drop policy if exists statement_transactions_finance_insert on public.statement_transactions;
create policy statement_transactions_finance_insert on public.statement_transactions
  for insert to authenticated
  with check (
    public.has_business_role(business_id,array['owner','admin','manager','accountant']::public.business_role[])
    and exists (select 1 from public.statement_imports i
      where i.id = import_id and i.business_id = statement_transactions.business_id)
  );

drop policy if exists statement_transactions_finance_update on public.statement_transactions;
create policy statement_transactions_finance_update on public.statement_transactions
  for update to authenticated
  using (public.has_business_role(business_id,array['owner','admin','manager','accountant']::public.business_role[]))
  with check (
    public.has_business_role(business_id,array['owner','admin','manager','accountant']::public.business_role[])
    and (cashbook_entry_id is null or exists (
      select 1 from public.cashbook_entries c
      where c.id = cashbook_entry_id and c.business_id = statement_transactions.business_id
    ))
  );

drop policy if exists statement_imports_finance_update on public.statement_imports;
create policy statement_imports_finance_update on public.statement_imports
  for update to authenticated
  using (public.has_business_role(business_id,array['owner','admin','manager','accountant']::public.business_role[]))
  with check (public.has_business_role(business_id,array['owner','admin','manager','accountant']::public.business_role[]));

create unique index if not exists statement_transactions_one_cashbook_match_idx
  on public.statement_transactions(cashbook_entry_id) where cashbook_entry_id is not null;

grant select, insert, update, delete on public.statement_imports to authenticated;
grant select, insert, update on public.statement_transactions to authenticated;

commit;
