-- Developer account administration audit index.
-- Account creation and profile updates are performed by the manage-platform-accounts
-- Edge Function using the Supabase service role after developer identity verification.
begin;

create index if not exists platform_audit_logs_auth_account_events_idx
  on public.platform_audit_logs (entity_table, entity_id, occurred_at desc)
  where entity_table = 'auth.users';

commit;
