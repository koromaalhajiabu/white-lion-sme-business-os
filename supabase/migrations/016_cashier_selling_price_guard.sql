-- White Lion SME Business OS
-- Enforce catalogue selling prices for cashiers at the database boundary.
-- Owners, admins and managers may apply an override; each override is audited.
-- This protects offline sync and any future client from trusting a submitted price.

begin;

create or replace function public.enforce_offline_sale_item_price()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_role public.business_role;
  v_standard_price numeric(18,2);
begin
  if auth.uid() is null then
    raise exception 'Authenticated user required to post a sale item';
  end if;

  select bm.role
    into v_role
  from public.business_members bm
  where bm.business_id = new.business_id
    and bm.user_id = auth.uid()
    and bm.is_active = true;

  if v_role is null then
    raise exception 'Active business membership required';
  end if;

  select p.selling_price
    into v_standard_price
  from public.products p
  where p.id = new.product_id
    and p.business_id = new.business_id
    and p.is_active = true;

  if not found then
    raise exception 'Active product not found in this business';
  end if;

  if new.unit_price <> v_standard_price then
    if v_role = 'cashier' then
      raise exception 'Cashiers must use the catalogue selling price. Ask a manager to approve a price override.';
    end if;

    if v_role not in ('owner','admin','manager') then
      raise exception 'Your role cannot override product selling prices';
    end if;

    insert into public.audit_logs (
      business_id,
      actor_user_id,
      action,
      entity_table,
      entity_id,
      details
    )
    values (
      new.business_id,
      auth.uid(),
      'sale_price_override',
      'offline_sale_items',
      new.id::text,
      jsonb_build_object(
        'sale_id', new.sale_id,
        'product_id', new.product_id,
        'catalogue_price', v_standard_price,
        'charged_price', new.unit_price,
        'quantity', new.quantity,
        'line_total', new.line_total
      )
    );
  end if;

  return new;
end;
$$;

revoke all on function public.enforce_offline_sale_item_price() from public;
revoke all on function public.enforce_offline_sale_item_price() from anon, authenticated;

drop trigger if exists trg_enforce_offline_sale_item_price
on public.offline_sale_items;

create trigger trg_enforce_offline_sale_item_price
before insert or update of business_id, product_id, unit_price, quantity, line_total
on public.offline_sale_items
for each row
execute function public.enforce_offline_sale_item_price();

commit;
