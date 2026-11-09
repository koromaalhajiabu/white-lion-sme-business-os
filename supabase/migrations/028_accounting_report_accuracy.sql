-- White Lion SME Business OS — Migration 028
-- Correct accounting report date/status filtering.
-- The earlier report functions joined journal_entries with date/status conditions
-- but aggregated journal_lines without filtering on the matched journal entry.
-- This migration aggregates only posted journal entries inside the requested period.
begin;

create or replace function public.accounting_reporting_version()
returns integer
language sql
immutable
security definer
set search_path=''
as $$
  select 2;
$$;

create or replace function public.accounting_income_statement(
  p_business_id uuid,
  p_from date default date_trunc('month',current_date)::date,
  p_to date default current_date
) returns table(account_code text,account_name text,account_type text,amount numeric)
language plpgsql
security definer
set search_path=''
as $$
begin
  if auth.uid() is null or not public.has_business_role(
    p_business_id,array['owner','admin','manager','accountant']::public.business_role[]
  ) then
    raise exception 'Not authorised to view accounting reports';
  end if;

  return query
  with posted as (
    select l.account_id,
      coalesce(sum(l.debit),0)::numeric as debits,
      coalesce(sum(l.credit),0)::numeric as credits
    from public.journal_lines l
    join public.journal_entries j
      on j.id=l.journal_entry_id and j.business_id=l.business_id
    where l.business_id=p_business_id
      and j.status='posted'
      and j.journal_date between coalesce(p_from,'0001-01-01'::date)
                             and coalesce(p_to,current_date)
    group by l.account_id
  )
  select a.account_code,a.account_name,a.account_type,
    case when a.account_type='income'
      then coalesce(p.credits-p.debits,0)
      else coalesce(p.debits-p.credits,0)
    end::numeric
  from public.chart_of_accounts a
  left join posted p on p.account_id=a.id
  where a.business_id=p_business_id
    and a.is_active
    and a.account_type in ('income','expense')
  order by a.account_code;
end;
$$;

create or replace function public.accounting_trial_balance(
  p_business_id uuid,
  p_from date default null,
  p_to date default current_date
) returns table(
  account_code text,
  account_name text,
  account_type text,
  total_debit numeric,
  total_credit numeric,
  net_balance numeric
)
language plpgsql
security definer
set search_path=''
as $$
begin
  if auth.uid() is null or not public.has_business_role(
    p_business_id,array['owner','admin','manager','accountant']::public.business_role[]
  ) then
    raise exception 'Not authorised to view accounting reports';
  end if;

  return query
  with posted as (
    select l.account_id,
      coalesce(sum(l.debit),0)::numeric as debits,
      coalesce(sum(l.credit),0)::numeric as credits
    from public.journal_lines l
    join public.journal_entries j
      on j.id=l.journal_entry_id and j.business_id=l.business_id
    where l.business_id=p_business_id
      and j.status='posted'
      and j.journal_date<=coalesce(p_to,current_date)
      and (p_from is null or j.journal_date>=p_from)
    group by l.account_id
  )
  select a.account_code,a.account_name,a.account_type,
    coalesce(p.debits,0)::numeric,
    coalesce(p.credits,0)::numeric,
    case when a.normal_balance='debit'
      then coalesce(p.debits-p.credits,0)
      else coalesce(p.credits-p.debits,0)
    end::numeric
  from public.chart_of_accounts a
  left join posted p on p.account_id=a.id
  where a.business_id=p_business_id and a.is_active
  order by a.account_code;
end;
$$;

create or replace function public.accounting_balance_sheet(
  p_business_id uuid,
  p_as_of date default current_date
) returns table(account_code text,account_name text,account_type text,amount numeric)
language plpgsql
security definer
set search_path=''
as $$
begin
  if auth.uid() is null or not public.has_business_role(
    p_business_id,array['owner','admin','manager','accountant']::public.business_role[]
  ) then
    raise exception 'Not authorised to view accounting reports';
  end if;

  return query
  with posted as (
    select l.account_id,
      coalesce(sum(l.debit),0)::numeric as debits,
      coalesce(sum(l.credit),0)::numeric as credits
    from public.journal_lines l
    join public.journal_entries j
      on j.id=l.journal_entry_id and j.business_id=l.business_id
    where l.business_id=p_business_id
      and j.status='posted'
      and j.journal_date<=coalesce(p_as_of,current_date)
    group by l.account_id
  )
  select a.account_code,a.account_name,a.account_type,
    case when a.normal_balance='debit'
      then coalesce(p.debits-p.credits,0)
      else coalesce(p.credits-p.debits,0)
    end::numeric
  from public.chart_of_accounts a
  left join posted p on p.account_id=a.id
  where a.business_id=p_business_id
    and a.is_active
    and a.account_type in ('asset','liability','equity')

  union all

  select '3999'::text,'Accumulated earnings (unclosed)'::text,'equity'::text,
    coalesce(sum(
      case when a.account_type='income'
        then p.credits-p.debits
        else p.debits-p.credits
      end
    ),0)::numeric
  from public.chart_of_accounts a
  join posted p on p.account_id=a.id
  where a.business_id=p_business_id
    and a.account_type in ('income','expense')
  order by 3,1;
end;
$$;

revoke all on function public.accounting_reporting_version() from public,anon;
revoke all on function public.accounting_income_statement(uuid,date,date) from public,anon;
revoke all on function public.accounting_trial_balance(uuid,date,date) from public,anon;
revoke all on function public.accounting_balance_sheet(uuid,date) from public,anon;

grant execute on function public.accounting_reporting_version() to authenticated;
grant execute on function public.accounting_income_statement(uuid,date,date) to authenticated;
grant execute on function public.accounting_trial_balance(uuid,date,date) to authenticated;
grant execute on function public.accounting_balance_sheet(uuid,date) to authenticated;

commit;
