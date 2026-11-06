begin;

-- Developer-only reset for demonstration/business data.
-- Preserves auth.users (including the developer login), developer allow-list,
-- platform settings, platform audit history, and account recovery history.
create or replace function public.reset_platform_business_data()
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_business_count integer;
begin
  if not public.is_platform_developer() then
    raise exception 'Private developer account required';
  end if;

  select count(*) into v_business_count from public.businesses;
  delete from public.businesses;

  -- Keep a platform-level record independent of deleted business workspaces.
  if to_regclass('public.platform_audit_logs') is not null then
    insert into public.platform_audit_logs(
      business_id, actor_user_id, action, entity_table, entity_id, details, occurred_at
    ) values (
      null, auth.uid(), 'platform_business_data_reset', 'businesses', null,
      jsonb_build_object('deleted_business_workspaces', v_business_count), now()
    );
  end if;

  return jsonb_build_object(
    'success', true,
    'deleted_business_workspaces', v_business_count,
    'developer_account_preserved', true,
    'auth_accounts_preserved', true
  );
end;
$$;

revoke all on function public.reset_platform_business_data() from public, anon;
grant execute on function public.reset_platform_business_data() to authenticated;

commit;
