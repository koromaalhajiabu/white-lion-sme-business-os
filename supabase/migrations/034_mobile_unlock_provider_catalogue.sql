begin;
create table if not exists public.phone_unlocking_provider_services (
 id uuid primary key default gen_random_uuid(),
 business_id uuid not null references public.businesses(id) on delete cascade,
 provider_service_id text not null,
 provider_service_type text not null default 'IMEI',
 provider_group text,
 service_name text not null,
 provider_credit numeric(18,4),
 provider_currency text,
 delivery_time text,
 description text,
 quantity integer,
 requires_custom jsonb not null default '[]'::jsonb,
 is_active boolean not null default true,
 last_synced_at timestamptz not null default now(),
 created_at timestamptz not null default now(),
 updated_at timestamptz not null default now(),
 unique (business_id,provider_service_type,provider_service_id)
);
alter table public.phone_unlocking_services
 add column if not exists provider_service_id text,
 add column if not exists provider_service_type text,
 add column if not exists provider_group text,
 add column if not exists provider_cost numeric(18,4),
 add column if not exists provider_currency text,
 add column if not exists provider_delivery_time text,
 add column if not exists provider_info text,
 add column if not exists provider_requires_custom jsonb;
create unique index if not exists phone_unlocking_services_provider_unique
 on public.phone_unlocking_services(business_id,provider_service_type,provider_service_id)
 where provider_service_id is not null;
create index if not exists phone_unlocking_provider_services_business_idx
 on public.phone_unlocking_provider_services(business_id,is_active,provider_group,service_name);
alter table public.phone_unlocking_provider_services enable row level security;
drop policy if exists phone_unlocking_provider_services_read on public.phone_unlocking_provider_services;
create policy phone_unlocking_provider_services_read on public.phone_unlocking_provider_services
 for select to authenticated using (public.has_business_role(business_id,array['owner','admin','manager']::public.business_role[]));
drop policy if exists phone_unlocking_provider_services_manage on public.phone_unlocking_provider_services;
create policy phone_unlocking_provider_services_manage on public.phone_unlocking_provider_services
 for all to authenticated using (public.has_business_role(business_id,array['owner','admin','manager']::public.business_role[]))
 with check (public.has_business_role(business_id,array['owner','admin','manager']::public.business_role[]));
revoke all on public.phone_unlocking_provider_services from anon;
grant select,insert,update on public.phone_unlocking_provider_services to authenticated;
commit;