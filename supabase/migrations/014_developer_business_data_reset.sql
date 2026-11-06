begin;

-- Private developer reset. Business data is removed; non-developer accounts
-- are disabled immediately and queued for the existing 30-day recovery period.
-- The developer login and all platform-level audit/recovery history are retained.
create or replace function public.reset_platform_business_data()
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_business_count integer;
  v_account_count integer := 0;
  v_user record;
  v_previous_active boolean;
begin
  if not public.is_platform_developer() then
    raise exception 'Private developer account required';
  end if;

  select count(*) into v_business_count from public.businesses;

  -- Remove restrictive return references before cascading business workspaces.
  delete from public.offline_sale_return_items;
  delete from public.offline_sale_returns;
  delete from public.businesses;

  -- Deactivate all non-developer logins now, preserving a 30-day recovery path.
  for v_user in
    select u.id, lower(u.email) as email
    from auth.users u
    where u.email is not null
      and not exists (
        select 1 from public.platform_developer_emails d
        where lower(d.email) = lower(u.email)
      )
      and not exists (
        select 1 from public.platform_account_deletion_requests r
        where r.target_user_id = u.id and r.status = 'pending'
      )
  loop
    select coalesce(a.is_active, true) into v_previous_active
    from public.platform_account_access a where a.user_id = v_user.id;
    v_previous_active := coalesce(v_previous_active, true);

    insert into public.platform_account_deletion_requests(
      target_user_id, target_email, requested_by, previous_is_active
    ) values (
      v_user.id, v_user.email, auth.uid(), v_previous_active
    );

    insert into public.platform_account_access(
      user_id, is_active, note, updated_by, updated_at
    ) values (
      v_user.id, false, 'Platform reset; 30-day account recovery period',
      auth.uid(), now()
    )
    on conflict (user_id) do update set
      is_active = false,
      note = 'Platform reset; 30-day account recovery period',
      updated_by = auth.uid(),
      updated_at = now();

    v_account_count := v_account_count + 1;
  end loop;

  if to_regclass('public.platform_audit_logs') is not null then
    insert into public.platform_audit_logs(
      business_id, actor_user_id, action, entity_table, entity_id, details, occurred_at
    ) values (
      null, auth.uid(), 'platform_business_data_reset', 'businesses', null,
      jsonb_build_object(
        'deleted_business_workspaces', v_business_count,
        'accounts_queued_for_30_day_deletion', v_account_count
      ), now()
    );
  end if;

  return jsonb_build_object(
    'success', true,
    'deleted_business_workspaces', v_business_count,
    'accounts_queued_for_30_day_deletion', v_account_count,
    'developer_account_preserved', true
  );
end;
$$;

revoke all on function public.reset_platform_business_data() from public, anon;
grant execute on function public.reset_platform_business_data() to authenticated;

commit;
