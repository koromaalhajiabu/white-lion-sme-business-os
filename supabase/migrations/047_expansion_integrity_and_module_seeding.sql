-- White Lion SME Business OS — Migration 047
-- Completes supplier-portal self-discovery, future-business module seeding,
-- and maintains loyalty balances from the immutable loyalty ledger.
begin;

-- New businesses receive the expansion modules too; they remain disabled by default.
create or replace function public.seed_expansion_modules_for_business()
returns trigger language plpgsql security definer set search_path=public
as $$
begin
  insert into public.business_industry_modules(business_id,module_key,is_enabled)
  values
    (new.id,'payroll',false),
    (new.id,'customer_loyalty',false),
    (new.id,'online_store',false),
    (new.id,'supplier_portal',false),
    (new.id,'business_marketplace',false),
    (new.id,'franchise_management',false)
  on conflict (business_id,module_key) do nothing;
  return new;
end;
$$;
drop trigger if exists trg_seed_expansion_modules on public.businesses;
create trigger trg_seed_expansion_modules after insert on public.businesses
for each row execute function public.seed_expansion_modules_for_business();

-- Supplier portal users can read only their own active portal membership row.
drop policy if exists supplier_portal_member_self_read on public.supplier_portal_members;
create policy supplier_portal_member_self_read on public.supplier_portal_members
for select to authenticated using (user_id=auth.uid() and is_active=true);

-- Keep loyalty balances consistent with the append-only ledger.
create or replace function public.apply_customer_loyalty_ledger_entry()
returns trigger language plpgsql security definer set search_path=public
as $$
begin
  insert into public.customer_loyalty_accounts
    (business_id,customer_id,points_balance,lifetime_points,updated_at)
  values
    (new.business_id,new.customer_id,new.points_delta,
     greatest(new.points_delta,0),now())
  on conflict (business_id,customer_id) do update
  set points_balance=public.customer_loyalty_accounts.points_balance+new.points_delta,
      lifetime_points=public.customer_loyalty_accounts.lifetime_points+
        greatest(new.points_delta,0),
      updated_at=now();
  return new;
end;
$$;
drop trigger if exists trg_apply_customer_loyalty_ledger on public.customer_loyalty_ledger;
create trigger trg_apply_customer_loyalty_ledger
after insert on public.customer_loyalty_ledger
for each row execute function public.apply_customer_loyalty_ledger_entry();

-- Prevent a negative balance even if concurrent redemptions are submitted.
create or replace function public.guard_customer_loyalty_balance()
returns trigger language plpgsql security definer set search_path=public
as $$
declare v_balance bigint;
begin
  select points_balance into v_balance
  from public.customer_loyalty_accounts
  where business_id=new.business_id and customer_id=new.customer_id
  for update;
  if coalesce(v_balance,0)+new.points_delta < 0 then
    raise exception 'Insufficient loyalty points for this redemption';
  end if;
  return new;
end;
$$;
drop trigger if exists trg_guard_customer_loyalty_balance on public.customer_loyalty_ledger;
create trigger trg_guard_customer_loyalty_balance
before insert on public.customer_loyalty_ledger
for each row execute function public.guard_customer_loyalty_balance();

commit;
