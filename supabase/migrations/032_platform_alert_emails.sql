-- White Lion SME Business OS — email alerts to the platform developer
-- for new account registrations and subscription payment submissions.
-- Uses pg_net (async HTTP) + Supabase Vault (encrypted secret storage) to
-- call the Resend email API directly from the database, so an alert can
-- never block or fail the signup/payment it reports on.
-- Run after migrations 001-031. Safe to rerun.
begin;

create extension if not exists pg_net;

-- Single-row settings table so the alert destination can be changed later
-- (e.g. from the developer panel) without a new migration.
create table if not exists public.platform_alert_settings (
  id boolean primary key default true check (id),
  alert_email text not null,
  alerts_enabled boolean not null default true,
  updated_at timestamptz not null default now()
);

insert into public.platform_alert_settings (id, alert_email)
values (true, 'koromaalhajiabu0@gmail.com')
on conflict (id) do nothing;

alter table public.platform_alert_settings enable row level security;
revoke all on public.platform_alert_settings from anon, authenticated;

create or replace function public.get_platform_alert_settings()
returns table (alert_email text, alerts_enabled boolean)
language plpgsql
stable
security definer
set search_path = ''
as $$
begin
  if not public.is_platform_developer() then
    raise exception 'Developer access required';
  end if;
  return query select s.alert_email, s.alerts_enabled from public.platform_alert_settings s where s.id = true;
end;
$$;

create or replace function public.set_platform_alert_settings(p_alert_email text, p_alerts_enabled boolean)
returns void
language plpgsql
security definer
set search_path = ''
as $$
begin
  if not public.is_platform_developer() then
    raise exception 'Developer access required';
  end if;
  if p_alert_email is null or position('@' in p_alert_email) < 2 then
    raise exception 'Enter a valid email address';
  end if;
  update public.platform_alert_settings
  set alert_email = lower(trim(p_alert_email)), alerts_enabled = coalesce(p_alerts_enabled, true), updated_at = now()
  where id = true;
end;
$$;

revoke all on function public.get_platform_alert_settings() from public, anon;
revoke all on function public.set_platform_alert_settings(text, boolean) from public, anon;
grant execute on function public.get_platform_alert_settings() to authenticated;
grant execute on function public.set_platform_alert_settings(text, boolean) to authenticated;

-- Core sender: looks up the Resend API key from Vault and the destination
-- address from platform_alert_settings, then fires an async HTTP request.
-- Any failure (missing key, network hiccup) is swallowed so it can never
-- roll back the registration or payment that triggered it.
create or replace function public.send_platform_alert_email(p_subject text, p_html text)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_api_key text;
  v_to_email text;
  v_enabled boolean;
begin
  select alert_email, alerts_enabled into v_to_email, v_enabled
  from public.platform_alert_settings where id = true;
  if v_to_email is null or coalesce(v_enabled, true) = false then
    return;
  end if;

  select decrypted_secret into v_api_key
  from vault.decrypted_secrets where name = 'resend_api_key' limit 1;
  if v_api_key is null or length(trim(v_api_key)) = 0 then
    return;
  end if;

  perform net.http_post(
    url := 'https://api.resend.com/emails',
    headers := jsonb_build_object(
      'Authorization', 'Bearer ' || v_api_key,
      'Content-Type', 'application/json'
    ),
    body := jsonb_build_object(
      'from', 'White Lion Alerts <onboarding@resend.dev>',
      'to', jsonb_build_array(v_to_email),
      'subject', p_subject,
      'html', p_html
    )
  );
exception when others then
  null;
end;
$$;

revoke all on function public.send_platform_alert_email(text, text) from public, anon, authenticated;

-- Alert on genuinely new account registrations.
-- platform_registration_notifications is only INSERTed into for a brand
-- new auth.users row (repeat sign-ins/confirmations go through the
-- ON CONFLICT DO UPDATE branch of capture_platform_registration), so an
-- AFTER INSERT trigger here fires exactly once per new account.
create or replace function public.notify_new_registration()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  perform public.send_platform_alert_email(
    'New account registered — White Lion',
    '<p>A new account just registered on White Lion SME Business OS.</p>' ||
    '<p><b>Email:</b> ' || coalesce(new.email, '') || '</p>' ||
    '<p><b>Name:</b> ' || coalesce(nullif(new.full_name, ''), '(not provided)') || '</p>' ||
    '<p><b>Registered at:</b> ' || to_char(new.registered_at, 'YYYY-MM-DD HH24:MI') || ' UTC</p>'
  );
  return new;
end;
$$;

drop trigger if exists notify_new_registration on public.platform_registration_notifications;
create trigger notify_new_registration
after insert on public.platform_registration_notifications
for each row execute function public.notify_new_registration();

-- Alert whenever a business submits (attempts) a subscription payment for
-- developer review — this is the platform's only payment flow.
create or replace function public.notify_payment_submission()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_business_name text;
  v_invoice_number text;
begin
  select b.name into v_business_name from public.businesses b where b.id = new.business_id;
  select si.invoice_number into v_invoice_number from public.subscription_invoices si where si.id = new.invoice_id;
  perform public.send_platform_alert_email(
    'Payment submitted — ' || coalesce(v_business_name, 'White Lion'),
    '<p>A business just submitted a subscription payment for review.</p>' ||
    '<p><b>Business:</b> ' || coalesce(v_business_name, '(unknown)') || '</p>' ||
    '<p><b>Invoice:</b> ' || coalesce(v_invoice_number, '') || '</p>' ||
    '<p><b>Provider:</b> ' || new.provider || '</p>' ||
    '<p><b>Reference:</b> ' || new.payment_reference || '</p>' ||
    '<p><b>Amount:</b> ' || new.amount || ' ' || new.currency_code || '</p>' ||
    '<p>Review it from your developer panel.</p>'
  );
  return new;
end;
$$;

drop trigger if exists notify_payment_submission on public.subscription_payments;
create trigger notify_payment_submission
after insert on public.subscription_payments
for each row execute function public.notify_payment_submission();

commit;
