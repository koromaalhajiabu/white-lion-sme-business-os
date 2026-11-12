-- White Lion SME Business OS — Migration 045
-- Historical ledger backfill, opening balances, reversals and accounting period close.
-- Safe to rerun: every source is uniquely identified and already-posted sources are skipped.
begin;

create table if not exists public.accounting_journal_reversals (
  id uuid primary key default gen_random_uuid(),
  business_id uuid not null references public.businesses(id) on delete cascade,
  original_journal_id uuid not null,
  reversal_journal_id uuid not null,
  reason text not null check (length(trim(reason)) between 3 and 500),
  created_by uuid not null default auth.uid() references auth.users(id),
  created_at timestamptz not null default now(),
  unique (business_id, original_journal_id),
  unique (business_id, reversal_journal_id),
  foreign key (original_journal_id,business_id)
    references public.journal_entries(id,business_id) on delete restrict,
  foreign key (reversal_journal_id,business_id)
    references public.journal_entries(id,business_id) on delete restrict
);

create table if not exists public.accounting_period_closes (
  id uuid primary key default gen_random_uuid(),
  business_id uuid not null references public.businesses(id) on delete cascade,
  period_start date not null,
  period_end date not null,
  closing_journal_id uuid not null,
  closed_by uuid references auth.users(id),
  closed_at timestamptz not null default now(),
  check (period_end >= period_start),
  unique (business_id,period_start,period_end),
  foreign key (closing_journal_id,business_id)
    references public.journal_entries(id,business_id) on delete restrict
);

alter table public.accounting_journal_reversals enable row level security;
alter table public.accounting_period_closes enable row level security;
drop policy if exists accounting_reversals_finance_read on public.accounting_journal_reversals;
create policy accounting_reversals_finance_read on public.accounting_journal_reversals
for select to authenticated using (
  public.has_business_role(business_id,array['owner','admin','manager','accountant']::public.business_role[])
);
drop policy if exists accounting_period_closes_finance_read on public.accounting_period_closes;
create policy accounting_period_closes_finance_read on public.accounting_period_closes
for select to authenticated using (
  public.has_business_role(business_id,array['owner','admin','manager','accountant']::public.business_role[])
);
revoke all on public.accounting_journal_reversals,public.accounting_period_closes from anon,public,authenticated;
grant select on public.accounting_journal_reversals,public.accounting_period_closes to authenticated;

-- Prevent new journals being posted into a closed period. The period-close journal
-- itself is allowed to post on the period's final day.
create or replace function public.guard_closed_accounting_period()
returns trigger language plpgsql security definer set search_path=''
as $$
begin
  if new.source_type <> 'period_close' and exists (
    select 1 from public.accounting_period_closes c
    where c.business_id=new.business_id
      and new.journal_date between c.period_start and c.period_end
  ) then
    raise exception 'This accounting period is closed. Use a current-period adjustment or an authorised reversal.';
  end if;
  return new;
end;
$$;
drop trigger if exists trg_guard_closed_accounting_period on public.journal_entries;
create trigger trg_guard_closed_accounting_period
before insert on public.journal_entries
for each row execute function public.guard_closed_accounting_period();

-- Import posted historical transactions once. Historical COGS is used only where
-- a recorded unit cost or inventory-cost movement exists; no current cost is guessed.
create or replace function public.backfill_accounting_history(p_business_id uuid)
returns jsonb language plpgsql security definer set search_path=''
as $$
declare
  r record;
  v_lines jsonb;
  v_cogs numeric(18,2);
  v_done_sales integer:=0;
  v_done_purchases integer:=0;
  v_done_expenses integer:=0;
  v_skipped integer:=0;
  v_journal uuid;
begin
  if auth.uid() is null or not public.has_business_role(
    p_business_id,array['owner','admin','accountant']::public.business_role[]
  ) then raise exception 'Only an owner, administrator or accountant can backfill accounting history'; end if;
  perform public.seed_default_chart_of_accounts(p_business_id);

  for r in select s.* from public.sales s
    where s.business_id=p_business_id and s.status::text='posted'
      and not exists(select 1 from public.journal_entries j where j.business_id=s.business_id and j.source_type='legacy_sale' and j.source_id=s.id::text)
    order by s.created_at,s.id
  loop
    v_cogs:=0;
    select coalesce(sum(round(i.quantity*i.unit_cost,2)),0) into v_cogs
    from public.sale_items i where i.business_id=r.business_id and i.sale_id=r.id;
    v_lines:='[]'::jsonb;
    if least(coalesce(r.amount_paid,0),r.total)>0 then
      v_lines:=v_lines||jsonb_build_array(jsonb_build_object('code','1000','debit',least(r.amount_paid,r.total),'credit',0,'description','Cash received'));
    end if;
    if greatest(r.total-least(coalesce(r.amount_paid,0),r.total),0)>0 then
      v_lines:=v_lines||jsonb_build_array(jsonb_build_object('code','1100','debit',greatest(r.total-least(coalesce(r.amount_paid,0),r.total),0),'credit',0,'description','Customer receivable'));
    end if;
    v_lines:=v_lines||jsonb_build_array(jsonb_build_object('code','4000','debit',0,'credit',r.total,'description','Historical sales revenue'));
    if v_cogs>0 then
      v_lines:=v_lines||jsonb_build_array(
        jsonb_build_object('code','5000','debit',v_cogs,'credit',0,'description','Recorded historical cost of goods sold'),
        jsonb_build_object('code','1200','debit',0,'credit',v_cogs,'description','Inventory relieved')
      );
    end if;
    if r.total>0 then
      v_journal:=public.post_system_journal(r.business_id,r.created_at::date,
        'Historical sale · '||r.reference,'legacy_sale',r.id::text,v_lines);
      v_done_sales:=v_done_sales+1;
    else v_skipped:=v_skipped+1; end if;
  end loop;

  for r in select s.* from public.offline_sales s
    where s.business_id=p_business_id
      and not exists(select 1 from public.journal_entries j where j.business_id=s.business_id and j.source_type='offline_sale' and j.source_id=s.id::text)
    order by s.created_at,s.id
  loop
    select coalesce(sum(m.total_cost),0) into v_cogs
    from public.inventory_cost_movements m
    where m.business_id=r.business_id and m.source_type='offline_sales'
      and m.source_id=r.id::text and m.movement_type='sale';
    v_lines:=jsonb_build_array(
      jsonb_build_object('code',case when lower(coalesce(r.payment_method,'')) in ('credit','on credit','accounts receivable') then '1100' else '1000' end,
        'debit',r.total,'credit',0,'description','Historical sale proceeds'),
      jsonb_build_object('code','4000','debit',0,'credit',r.total,'description','Historical sales revenue')
    );
    if v_cogs>0 then
      v_lines:=v_lines||jsonb_build_array(
        jsonb_build_object('code','5000','debit',v_cogs,'credit',0,'description','Recorded historical cost of goods sold'),
        jsonb_build_object('code','1200','debit',0,'credit',v_cogs,'description','Inventory relieved')
      );
    end if;
    if r.total>0 then
      v_journal:=public.post_system_journal(r.business_id,r.transaction_date,
        'Historical offline sale · '||r.receipt,'offline_sale',r.id::text,v_lines);
      v_done_sales:=v_done_sales+1;
    else v_skipped:=v_skipped+1; end if;
  end loop;

  for r in select p.* from public.purchases p
    where p.business_id=p_business_id and p.status::text='posted'
      and not exists(select 1 from public.journal_entries j where j.business_id=p.business_id and j.source_type='legacy_purchase' and j.source_id=p.id::text)
    order by p.created_at,p.id
  loop
    if r.total>0 then
      v_lines:=jsonb_build_array(jsonb_build_object('code','1200','debit',r.total,'credit',0,'description','Historical inventory purchased'));
      if least(coalesce(r.amount_paid,0),r.total)>0 then
        v_lines:=v_lines||jsonb_build_array(jsonb_build_object('code','1000','debit',0,'credit',least(r.amount_paid,r.total),'description','Supplier payment'));
      end if;
      if greatest(r.total-least(coalesce(r.amount_paid,0),r.total),0)>0 then
        v_lines:=v_lines||jsonb_build_array(jsonb_build_object('code','2000','debit',0,'credit',greatest(r.total-least(coalesce(r.amount_paid,0),r.total),0),'description','Supplier payable'));
      end if;
      v_journal:=public.post_system_journal(r.business_id,r.created_at::date,
        'Historical purchase · '||r.reference,'legacy_purchase',r.id::text,v_lines);
      v_done_purchases:=v_done_purchases+1;
    else v_skipped:=v_skipped+1; end if;
  end loop;

  for r in select p.* from public.offline_purchases p
    where p.business_id=p_business_id
      and not exists(select 1 from public.journal_entries j where j.business_id=p.business_id and j.source_type='offline_purchase' and j.source_id=p.id::text)
    order by p.created_at,p.id
  loop
    if r.total>0 then
      v_journal:=public.post_system_journal(r.business_id,r.transaction_date,
        'Historical offline purchase · '||coalesce(r.supplier_name,'Supplier'),'offline_purchase',r.id::text,
        jsonb_build_array(
          jsonb_build_object('code','1200','debit',r.total,'credit',0,'description','Historical inventory purchased'),
          jsonb_build_object('code','2000','debit',0,'credit',r.total,'description','Supplier payable')
        ));
      v_done_purchases:=v_done_purchases+1;
    else v_skipped:=v_skipped+1; end if;
  end loop;

  for r in select rt.* from public.offline_sale_returns rt
    where rt.business_id=p_business_id and rt.refund_total>0
      and not exists(select 1 from public.journal_entries j where j.business_id=rt.business_id and j.source_type='sale_return' and j.source_id=rt.id::text)
    order by rt.created_at,rt.id
  loop
    v_journal:=public.post_system_journal(r.business_id,r.created_at::date,
      'Historical sales return · '||r.reason,'sale_return',r.id::text,
      jsonb_build_array(
        jsonb_build_object('code','4050','debit',r.refund_total,'credit',0,'description','Historical sales return'),
        jsonb_build_object('code','1000','debit',0,'credit',r.refund_total,'description','Historical refund paid')
      ));
  end loop;

  for r in select e.* from public.expenses e
    where e.business_id=p_business_id
      and not exists(select 1 from public.journal_entries j where j.business_id=e.business_id and j.source_type='expense' and j.source_id=e.id::text)
    order by e.created_at,e.id
  loop
    v_journal:=public.post_system_journal(r.business_id,r.expense_date,
      'Historical expense · '||r.category||' · '||r.description,'expense',r.id::text,
      jsonb_build_array(
        jsonb_build_object('code','6000','debit',r.amount,'credit',0,'description',r.category),
        jsonb_build_object('code','1000','debit',0,'credit',r.amount,'description','Cash / bank paid')
      ));
    v_done_expenses:=v_done_expenses+1;
  end loop;

  insert into public.audit_logs(business_id,actor_user_id,action,entity_table,details)
  values(p_business_id,auth.uid(),'accounting_history_backfilled','journal_entries',
    jsonb_build_object('sales',v_done_sales,'purchases',v_done_purchases,'expenses',v_done_expenses,'skipped',v_skipped));
  return jsonb_build_object('status','completed','sales_posted',v_done_sales,
    'purchases_posted',v_done_purchases,'expenses_posted',v_done_expenses,'historical_returns_processed',true,'zero_value_skipped',v_skipped,
    'note','Historical COGS is included only where a recorded cost exists; missing historical cost is not estimated.');
end;
$$;

-- Opening balances: provide debit/credit values for balance-sheet accounts only.
-- The function automatically balances the opening journal through Owner capital (3000).
create or replace function public.post_accounting_opening_balances(
  p_business_id uuid,p_effective_date date,p_balances jsonb
) returns uuid language plpgsql security definer set search_path=''
as $$
declare
  v_lines jsonb:='[]'::jsonb;
  v_item record;
  v_debits numeric(18,2):=0;
  v_credits numeric(18,2):=0;
  v_net numeric(18,2);
  v_journal uuid;
begin
  if auth.uid() is null or not public.has_business_role(
    p_business_id,array['owner','admin','accountant']::public.business_role[]
  ) then raise exception 'Only an owner, administrator or accountant can enter opening balances'; end if;
  if exists(select 1 from public.journal_entries where business_id=p_business_id and source_type='opening_balance') then
    raise exception 'Opening balances have already been posted for this business';
  end if;
  if jsonb_typeof(p_balances)<>'array' or jsonb_array_length(p_balances)=0 then
    raise exception 'Provide at least one opening balance line';
  end if;
  for v_item in select * from jsonb_to_recordset(p_balances) as x(code text,debit numeric,credit numeric) loop
    if v_item.code='3000' or v_item.code in ('4000','4050','4100','5000','6000','6100') then
      raise exception 'Opening balances accept balance-sheet accounts only; owner capital is calculated automatically';
    end if;
    if coalesce(v_item.debit,0)<0 or coalesce(v_item.credit,0)<0
      or (coalesce(v_item.debit,0)>0 and coalesce(v_item.credit,0)>0)
      or (coalesce(v_item.debit,0)=0 and coalesce(v_item.credit,0)=0) then
      raise exception 'Each opening line must have one positive debit or credit';
    end if;
    if not exists(select 1 from public.chart_of_accounts a where a.business_id=p_business_id
      and a.account_code=v_item.code and a.account_type in ('asset','liability','equity') and a.is_active) then
      raise exception 'Invalid or inactive balance-sheet account code: %',v_item.code;
    end if;
    v_debits:=v_debits+coalesce(v_item.debit,0);
    v_credits:=v_credits+coalesce(v_item.credit,0);
    v_lines:=v_lines||jsonb_build_array(jsonb_build_object('code',v_item.code,
      'debit',coalesce(v_item.debit,0),'credit',coalesce(v_item.credit,0),'description','Opening balance'));
  end loop;
  v_net:=v_debits-v_credits;
  if abs(v_net)>0.005 then
    if v_net>0 then
      v_lines:=v_lines||jsonb_build_array(jsonb_build_object('code','3000','debit',0,'credit',v_net,'description','Opening owner capital'));
    else
      v_lines:=v_lines||jsonb_build_array(jsonb_build_object('code','3000','debit',abs(v_net),'credit',0,'description','Opening owner capital'));
    end if;
  end if;
  if jsonb_array_length(v_lines)<2 then raise exception 'Opening balances must contain at least two lines'; end if;
  v_journal:=public.post_system_journal(p_business_id,p_effective_date,
    'Opening balances','opening_balance','initial',v_lines);
  insert into public.audit_logs(business_id,actor_user_id,action,entity_table,entity_id,details)
  values(p_business_id,auth.uid(),'opening_balances_posted','journal_entries',v_journal::text,
    jsonb_build_object('effective_date',p_effective_date,'debits',v_debits,'credits',v_credits,'capital_offset',v_net));
  return v_journal;
end;
$$;

-- Reverse a posted journal without editing or deleting its immutable original.
create or replace function public.reverse_accounting_journal(
  p_business_id uuid,p_journal_entry_id uuid,p_reversal_date date,p_reason text
) returns uuid language plpgsql security definer set search_path=''
as $$
declare
  v_original public.journal_entries%rowtype;
  v_lines jsonb;
  v_reversal uuid;
begin
  if auth.uid() is null or not public.has_business_role(
    p_business_id,array['owner','admin','accountant']::public.business_role[]
  ) then raise exception 'Only an owner, administrator or accountant can reverse journals'; end if;
  select * into v_original from public.journal_entries
  where id=p_journal_entry_id and business_id=p_business_id and status='posted';
  if not found then raise exception 'Posted journal not found'; end if;
  if exists(select 1 from public.accounting_journal_reversals
    where business_id=p_business_id and original_journal_id=p_journal_entry_id) then
    raise exception 'This journal has already been reversed';
  end if;
  if length(trim(coalesce(p_reason,'')))<3 then raise exception 'A reversal reason is required'; end if;
  select jsonb_agg(jsonb_build_object('code',a.account_code,'debit',l.credit,'credit',l.debit,
    'description','Reversal · '||coalesce(l.description,v_original.memo)))
  into v_lines
  from public.journal_lines l join public.chart_of_accounts a
    on a.id=l.account_id and a.business_id=l.business_id
  where l.journal_entry_id=p_journal_entry_id and l.business_id=p_business_id;
  v_reversal:=public.post_system_journal(p_business_id,p_reversal_date,
    'Reversal of journal '||v_original.entry_number||' · '||trim(p_reason),
    'reversal',p_journal_entry_id::text,v_lines);
  insert into public.accounting_journal_reversals(business_id,original_journal_id,reversal_journal_id,reason)
  values(p_business_id,p_journal_entry_id,v_reversal,trim(p_reason));
  insert into public.audit_logs(business_id,actor_user_id,action,entity_table,entity_id,details)
  values(p_business_id,auth.uid(),'journal_reversed','journal_entries',p_journal_entry_id::text,
    jsonb_build_object('reversal_journal_id',v_reversal,'reason',trim(p_reason)));
  return v_reversal;
end;
$$;

-- Close a financial period by transferring income/expense balances to retained earnings.
-- The period is locked after this function commits; corrections use a current-period reversal.
create or replace function public.close_accounting_period(
  p_business_id uuid,p_period_start date,p_period_end date
) returns uuid language plpgsql security definer set search_path=''
as $$
declare
  v_lines jsonb:='[]'::jsonb;
  r record;
  v_profit numeric(18,2):=0;
  v_journal uuid;
  v_source text;
begin
  if auth.uid() is null or not public.has_business_role(
    p_business_id,array['owner','admin','accountant']::public.business_role[]
  ) then raise exception 'Only an owner, administrator or accountant can close an accounting period'; end if;
  if p_period_start is null or p_period_end is null or p_period_end<p_period_start then
    raise exception 'A valid accounting period is required';
  end if;
  perform pg_advisory_xact_lock(hashtext(p_business_id::text||p_period_start::text||p_period_end::text));
  if exists(select 1 from public.accounting_period_closes where business_id=p_business_id
    and not (period_end<p_period_start or period_start>p_period_end)) then
    raise exception 'This period overlaps an already closed period';
  end if;
  for r in
    select a.account_code,a.account_name,a.account_type,
      round(coalesce(sum(case when a.account_type='income' then l.credit-l.debit else l.debit-l.credit end),0),2) as balance
    from public.chart_of_accounts a
    left join public.journal_lines l on l.account_id=a.id and l.business_id=a.business_id
    left join public.journal_entries j on j.id=l.journal_entry_id and j.business_id=l.business_id
      and j.status='posted' and j.journal_date between p_period_start and p_period_end
    where a.business_id=p_business_id and a.is_active and a.account_type in ('income','expense')
    group by a.account_code,a.account_name,a.account_type
    having abs(coalesce(sum(case when a.account_type='income' then l.credit-l.debit else l.debit-l.credit end),0))>0.005
    order by a.account_code
  loop
    if r.account_type='income' then
      if r.balance>0 then
        v_lines:=v_lines||jsonb_build_array(jsonb_build_object('code',r.account_code,'debit',r.balance,'credit',0,'description','Period close · '||r.account_name));
      else
        v_lines:=v_lines||jsonb_build_array(jsonb_build_object('code',r.account_code,'debit',0,'credit',abs(r.balance),'description','Period close · '||r.account_name));
      end if;
      v_profit:=v_profit+r.balance;
    else
      if r.balance>0 then
        v_lines:=v_lines||jsonb_build_array(jsonb_build_object('code',r.account_code,'debit',0,'credit',r.balance,'description','Period close · '||r.account_name));
      else
        v_lines:=v_lines||jsonb_build_array(jsonb_build_object('code',r.account_code,'debit',abs(r.balance),'credit',0,'description','Period close · '||r.account_name));
      end if;
      v_profit:=v_profit-r.balance;
    end if;
  end loop;
  if abs(v_profit)>0.005 then
    if v_profit>0 then
      v_lines:=v_lines||jsonb_build_array(jsonb_build_object('code','3200','debit',0,'credit',v_profit,'description','Net income transferred to retained earnings'));
    else
      v_lines:=v_lines||jsonb_build_array(jsonb_build_object('code','3200','debit',abs(v_profit),'credit',0,'description','Net loss transferred to retained earnings'));
    end if;
  end if;
  if jsonb_array_length(v_lines)<2 then raise exception 'There are no income or expense balances to close'; end if;
  v_source:=p_period_start::text||'|'||p_period_end::text;
  v_journal:=public.post_system_journal(p_business_id,p_period_end,
    'Period close · '||v_source,'period_close',v_source,v_lines);
  insert into public.accounting_period_closes(business_id,period_start,period_end,closing_journal_id)
  values(p_business_id,p_period_start,p_period_end,v_journal);
  insert into public.audit_logs(business_id,actor_user_id,action,entity_table,entity_id,details)
  values(p_business_id,auth.uid(),'accounting_period_closed','accounting_period_closes',v_journal::text,
    jsonb_build_object('period_start',p_period_start,'period_end',p_period_end,'net_result',v_profit));
  return v_journal;
end;
$$;

create or replace function public.accounting_workflow_version()
returns integer language sql immutable security definer set search_path=''
as $$ select 1; $$;

revoke all on function public.accounting_workflow_version() from public,anon;
revoke all on function public.guard_closed_accounting_period() from public;
revoke all on function public.backfill_accounting_history(uuid) from public;
revoke all on function public.post_accounting_opening_balances(uuid,date,jsonb) from public;
revoke all on function public.reverse_accounting_journal(uuid,uuid,date,text) from public;
revoke all on function public.close_accounting_period(uuid,date,date) from public;
grant execute on function public.accounting_workflow_version() to authenticated;
grant execute on function public.backfill_accounting_history(uuid) to authenticated;
grant execute on function public.post_accounting_opening_balances(uuid,date,jsonb) to authenticated;
grant execute on function public.reverse_accounting_journal(uuid,uuid,date,text) to authenticated;
grant execute on function public.close_accounting_period(uuid,date,date) to authenticated;

commit;
