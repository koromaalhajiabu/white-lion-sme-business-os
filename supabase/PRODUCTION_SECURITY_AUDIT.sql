-- WHITE LION SME BUSINESS OS — READ-ONLY PRODUCTION SECURITY AUDIT
-- Run in the Supabase SQL Editor for project nclncqlgnxnijlumznnt.
-- This file performs SELECT-only catalog checks. It does not alter data, policies or permissions.
-- Review every returned row against the platform's intended public/private access model.

-- 1. Public tables without Row Level Security.
-- Expected: no tenant-owned operational tables. Any result needs explicit review.
select
  n.nspname as schema_name,
  c.relname as table_name,
  c.relrowsecurity as rls_enabled,
  c.relforcerowsecurity as force_rls
from pg_class c
join pg_namespace n on n.oid = c.relnamespace
where n.nspname = 'public'
  and c.relkind in ('r','p')
  and not c.relrowsecurity
order by c.relname;

-- 2. Tables with RLS enabled but no policies.
-- Expected: review all rows; a table can intentionally deny all access, but this may also indicate an incomplete setup.
select
  n.nspname as schema_name,
  c.relname as table_name
from pg_class c
join pg_namespace n on n.oid = c.relnamespace
where n.nspname = 'public'
  and c.relkind in ('r','p')
  and c.relrowsecurity
  and not exists (
    select 1 from pg_policy p where p.polrelid = c.oid
  )
order by c.relname;

-- 3. Direct table privileges granted to anon or PUBLIC.
-- Review these individually. Public competition directory RPCs do not require public table grants.
select
  table_schema,
  table_name,
  grantee,
  privilege_type
from information_schema.role_table_grants
where table_schema = 'public'
  and grantee in ('anon','PUBLIC')
  and privilege_type in ('SELECT','INSERT','UPDATE','DELETE','TRUNCATE','REFERENCES','TRIGGER')
order by table_name, grantee, privilege_type;

-- 4. SECURITY DEFINER functions without an explicitly pinned search_path.
-- Review each result. SECURITY DEFINER functions should normally set a safe search_path
-- and schema-qualify referenced objects.
select
  n.nspname as schema_name,
  p.proname as function_name,
  pg_get_function_identity_arguments(p.oid) as arguments,
  p.proconfig as function_settings
from pg_proc p
join pg_namespace n on n.oid = p.pronamespace
where n.nspname = 'public'
  and p.prosecdef
  and not exists (
    select 1
    from unnest(coalesce(p.proconfig, array[]::text[])) setting
    where setting like 'search_path=%'
  )
order by p.proname;
