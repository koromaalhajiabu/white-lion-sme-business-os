# Secure account deletion — deployment checklist

This feature uses a 30-day recovery period. A request immediately suspends the target account's workspace access. It does not immediately remove the Supabase Auth identity.

## 1. Apply the database migration

Open the [White Lion Supabase SQL Editor](https://supabase.com/dashboard/project/nclncqlgnxnijlumznnt/sql/new), paste the complete contents of `supabase/migrations/008_account_deletion_recovery.sql`, and run it once.

The migration:
- Creates private deletion-request records and developer-only request/cancel/list RPCs.
- Requires the exact target email as confirmation.
- Protects the signed-in developer and all allowlisted developer emails.
- Blocks requests for accounts that own a business workspace.
- Starts a 30-day recovery window and suspends access immediately.
- Restores the account's previous active/suspended state when a request is cancelled.
- Changes user-reference foreign keys to preserve business records and audit history when a non-owner account is removed.
- Snapshots actor email in platform audit records so history remains readable.

## 2. Deploy the Edge Function

Open [Supabase Edge Functions](https://supabase.com/dashboard/project/nclncqlgnxnijlumznnt/functions).

Create a function named `process-account-deletions` and copy the source from `supabase/functions/process-account-deletions/index.ts`. Deploy it.

In the function's secrets, configure `SUPABASE_SERVICE_ROLE_KEY` with the project's service-role secret. Keep this secret only in Supabase Edge Function secrets. Never paste it into GitHub Pages, `index.html`, `cloud.js`, a public repository, or a chat.

Supabase supplies `SUPABASE_URL` and `SUPABASE_ANON_KEY` to Edge Functions. The function checks the caller's signed-in developer identity, the pending request, the elapsed 30-day period, the exact target email, developer protection, and business ownership again before removing the Auth identity.

## 3. How to use it

1. Open the live app and sign in using the private developer account.
2. In **Registered accounts**, select **Request deletion** for a non-owner account.
3. Type the account's exact email. The account is suspended immediately.
4. During the 30-day recovery period, use **Cancel & restore** to cancel the request. Its previous access state is restored.
5. After 30 days, **Permanently delete** becomes available. This is a separate, explicit action and invokes the Edge Function.

No automatic scheduled deletion is enabled. A developer must explicitly process each eligible request.

## Safety notes

- Accounts that own businesses cannot be requested for deletion. Transfer business ownership first; this workflow never deletes a business workspace.
- Membership rows for the deleted account are removed by their existing Auth foreign-key cascade. Business records remain, and creator/actor references are set to null where needed.
- A deletion request is not complete until the Edge Function succeeds.
- Test first with a disposable, non-owner test account. Do not test with a production owner or developer account.
