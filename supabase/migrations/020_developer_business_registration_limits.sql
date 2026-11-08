-- White Lion SME Business OS — Developer-controlled multiple-business permissions
-- Ordinary users default to one owned business. Platform Developer can grant a higher limit.
-- Existing business records and memberships are preserved.
begin;

create table if not exists public.platform_business_registration_limits (
  user_id uuid primary key references auth.users(id) on delete cascade,
  max_businesses integer not null check (max_businesses between 2 and 1000),
  granted_by uuid not null references auth.users(id),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

alter table public.platform_business_registration_limits enable row level security;
revoke all on public.platform_business_registration_limits from anon, authenticated, public;

create or replace function public.set_platform_business_registration_limit(
  p_email text,
  p_max_businesses integer
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_user_id uuid;
  v_email text;
  v_count integer;
begin
  if not public.is_platform_developer() then
    raise exception 'Developer access required';
  end if;

  v_email := lower(trim(coalesce(p_email, '')));
  if v_email = '' or position('@' in v_email) < 2 then
    raise exception 'Enter a valid registered email address';
  end if;

  select id, lower(email)
    into v_user_id, v_email
  from auth.users
  where lower(email) = lower(trim(p_email))
  limit 1;

  if v_user_id is null then
    raise exception 'No registered account found for that email';
  end if;

  if exists (
    select 1 from public.platform_developer_emails d
    where lower(d.email) = v_email
  ) then
    raise exception 'Platform Developer accounts already have unlimited business registration';
  end if;

  if p_max_businesses is null or p_max_businesses < 1 or p_max_businesses > 1000 then
    raise exception 'Maximum businesses must be between 1 and 1000';
  end if;

  select count(*)::integer into v_count
  from public.businesses
  where owner_user_id = v_user_id;

  if p_max_businesses = 1 then
    delete from public.platform_business_registration_limits
    where user_id = v_user_id;
  else
    insert into public.platform_business_registration_limits(
      user_id, max_businesses, granted_by, created_at, updated_at
    )
    values (v_user_id, p_max_businesses, auth.uid(), now(), now())
    on conflict (user_id) do update
    set max_businesses = excluded.max_businesses,
        granted_by = excluded.granted_by,
        updated_at = now();
  end if;

  if to_regclass('public.platform_audit_logs') is not null then
    insert into public.platform_audit_logs(
      business_id, actor_user_id, action, entity_table, entity_id, details, occurred_at
    )
    values (
      null, auth.uid(),
      case when p_max_businesses = 1 then 'business_registration_limit_revoked'
           else 'business_registration_limit_granted' end,
      'platform_business_registration_limits',
      v_user_id::text,
      jsonb_build_object(
        'target_email', v_email,
        'max_businesses', p_max_businesses,
        'existing_owned_businesses', v_count
      ),
      now()
    );
  end if;

  return jsonb_build_object(
    'success', true,
    'email', v_email,
    'max_businesses', p_max_businesses,
    'existing_owned_businesses', v_count,
    'permission', case when p_max_businesses = 1 then 'revoked' else 'granted' end
  );
end;
$$;

create or replace function public.get_platform_business_registration_limits()
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_result jsonb;
begin
  if not public.is_platform_developer() then
    raise exception 'Developer access required';
  end if;

  select coalesce(
    jsonb_agg(
      jsonb_build_object(
        'user_id', u.id,
        'email', u.email,
        'full_name', coalesce(u.raw_user_meta_data ->> 'full_name', u.raw_user_meta_data ->> 'name', ''),
        'max_businesses', l.max_businesses,
        'business_count', (
          select count(*)::integer
          from public.businesses b
          where b.owner_user_id = u.id
        ),
        'updated_at', l.updated_at
      )
      order by l.updated_at desc
    ),
    '[]'::jsonb
  )
  into v_result
  from public.platform_business_registration_limits l
  join auth.users u on u.id = l.user_id;

  return v_result;
end;
$$;

-- Replace business creation with a transaction-safe registration limit check.
create or replace function public.create_business(
  p_name text,
  p_industry text default 'Multi-industry',
  p_currency_code text default 'SLE'
)
returns uuid
language plpgsql
security definer
set search_path to 'public', 'auth'
as $function$
declare
  v_business_id uuid;
  v_user_id uuid;
  v_business_count integer;
  v_business_limit integer;
begin
  v_user_id := auth.uid();

  if v_user_id is null then
    raise exception 'Authentication required';
  end if;

  if length(trim(coalesce(p_name, ''))) < 2 then
    raise exception 'Business name is required';
  end if;

  -- Prevent concurrent requests from bypassing the user's limit.
  perform pg_advisory_xact_lock(hashtextextended(v_user_id::text, 0));

  if not public.is_platform_developer() then
    select count(*)::integer
      into v_business_count
    from public.businesses
    where owner_user_id = v_user_id;

    select coalesce(
      (select l.max_businesses
       from public.platform_business_registration_limits l
       where l.user_id = v_user_id),
      1
    )
    into v_business_limit;

    if v_business_count >= v_business_limit then
      raise exception
        'Business registration limit reached. Your current limit is % business(es). Contact the platform developer to request authorization for additional businesses.',
        v_business_limit;
    end if;
  end if;

  insert into public.businesses(name, industry, currency_code, owner_user_id)
  values (
    trim(p_name),
    coalesce(nullif(trim(p_industry), ''), 'Multi-industry'),
    upper(coalesce(nullif(trim(p_currency_code), ''), 'SLE')),
    v_user_id
  )
  returning id into v_business_id;

  insert into public.business_members(business_id, user_id, role)
  values (v_business_id, v_user_id, 'owner');

  insert into public.branches(business_id, name)
  values (v_business_id, 'Main Branch');

  insert into public.audit_logs(business_id, action, entity_table, entity_id)
  values (v_business_id, 'business_created', 'businesses', v_business_id::text);

  return v_business_id;
end;
$function$;

revoke all on function public.set_platform_business_registration_limit(text, integer) from public;
revoke all on function public.get_platform_business_registration_limits() from public;
grant execute on function public.set_platform_business_registration_limit(text, integer) to authenticated;
grant execute on function public.get_platform_business_registration_limits() to authenticated;
grant execute on function public.create_business(text, text, text) to authenticated;

commit;
