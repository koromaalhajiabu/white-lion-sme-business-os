# White Lion SME Business Operating System — Professional Readiness Review

Last reviewed: 12 November 2026

## Existing capabilities found in the repository

- GitHub Pages static frontend with installable PWA shell and service-worker caching.
- Supabase authentication, business memberships, tenant-scoped row-level security and business creation.
- Local IndexedDB records and offline transaction synchronisation with idempotency receipts.
- Multi-branch operations, branch membership, stock transfers and branch-aware transactions.
- Sales, purchasing, expenses, returns/refunds, cashbook, receivables/payables and payment recording.
- Inventory controls including barcode, batch/expiry tracking and controlled stock adjustments.
- Private business document storage with signed downloads.
- Sports and local-league competition, season, club, player, fixture, event and discipline schema.
- Developer account controls and audit logging.

These are repository-level findings. They do not independently prove every feature is correctly configured or functioning in the live Supabase project.

## Important gaps and risks

1. **A first double-entry ledger foundation is now implemented in migration 018.** It adds a chart of accounts, balanced immutable journal posting, source triggers for new cloud-synced sales/purchases/expenses/returns and obligation payments, manual journals, trial balance, income statement, balance sheet and cash-flow reports. This is not an audited accounting package. Migration 045 now adds an explicit, repeat-safe backfill for cloud historical posted sales, offline sales, purchases, expenses and recorded offline sale refunds; it uses historical COGS only where source cost records exist and does not estimate missing costs. It also adds one-time opening balance posting (with an automatic owner-capital balancing entry), immutable journal reversal records and accounting-period close locks. These workflows are database RPCs and require migration 045 to be applied and acceptance-tested in the live Supabase project. Local-only IndexedDB transactions must be synchronised before backfill. Manual cashbook entries are still not automatically journaled. The existing reports correctly label the operating balance as indicative rather than audited profit.
2. **Bank/mobile-money reconciliation was missing.** Migration 017 now adds a secure foundation for finance users to create bank/mobile-money accounts, import statement rows through an RPC, and match statement lines to cashbook entries. The operations control centre now includes a CSV import and matching interface. This is manual statement import; it is not a direct bank API connection. The interface still needs live Supabase and device acceptance testing.
3. **Backup automation is operational but recovery is not yet proven.** The GitHub Actions workflow exports table data and Auth user metadata through the Supabase REST API, private `business-documents` objects, and repository migrations, then encrypts the archive and retains it for 30 days. The workflow reads two Actions secrets: `SUPABASE_SERVICE_ROLE_KEY` and `BACKUP_ENCRYPTION_PASSPHRASE`; the project URL is currently set in the workflow file. A successful backup run exists on 10 November, but a full restore in a separate Supabase project remains mandatory. This is a logical JSON backup, not a physical or custom-format PostgreSQL dump.
4. **Offline conflict handling needs real multi-device tests.** Idempotent sync receipts exist, but test simultaneous edits, duplicate retries, partial network loss, device replacement and conflict recovery.
5. **Financial reports are operational summaries, not audited accounts.** Do not represent the current net sales less recorded expenses figure as net profit or available cash.
6. **Production security needs independent verification.** Test cross-business isolation with separate accounts, role escalation attempts, branch scoping, storage access, account recovery and audit coverage.
7. **Mobile/PWA quality needs device testing.** Test install/update behaviour, offline launch, theme persistence, language selection (including Arabic RTL), navigation, forms, keyboard handling, printing and small-screen tables on Android and iPhone.
8. **Subscription capability is partly implemented.** The repository contains plan definitions, trials, invoice/payment records, manual payment submission and administrator verification, plus capacity and expiry enforcement migrations. Direct Orange Money/AfriMoney/bank API checkout and automated recurring collection are not implemented or independently verified. The numbered migration files also contain legacy duplicate version labels (022 and 026); do not rely on Supabase CLI migration history until those historical files are reconciled against the live project's migration history.

## New changes in this release

- Added `supabase/migrations/018_double_entry_general_ledger.sql` and included it in `supabase/INSTALL_ALL_OPERATIONS.sql`.
- Added `supabase/migrations/019_weighted_average_inventory_cogs.sql` and included it in the consolidated installer.
- Added a finance UI for chart-of-accounts setup, trial balance, Profit & Loss, Balance Sheet, cash-flow reporting, inventory valuation and balanced manual journal posting.
- The ledger is designed to post new synced sales, purchases, expenses, returns and receivable/payable payments. Cash sales are routed to cash/bank; credit sales are routed to receivables. Historical records are not automatically rewritten.
- Migration 019 adds branch-level moving weighted-average inventory valuation, cost movement history, automatic COGS and inventory relief for new stock-managed synced sales, plus purchase, batch receipt, approved adjustment and branch-transfer valuation updates. Opening stock is valued using available batch costs and product.cost_price for unbatched quantities. Historical sales are not rewritten; historical COGS is not backfilled. Verify opening values before relying on gross profit.
- Manual cashbook entries are not automatically posted to the ledger in this release to avoid double-counting with existing payment workflows.
- Added `supabase/migrations/017_bank_mobile_money_reconciliation.sql`.
- Added the same migration to `supabase/INSTALL_ALL_OPERATIONS.sql` so the operations installer includes the new reconciliation schema and RPCs.
- Added a finance-only reconciliation interface to the Operations Control Centre: account setup, CSV statement import, unmatched-line review and guarded matching to cashbook entries.
- Linked new cashbook entries to a selected bank/mobile-money account so they can be reconciled later.
- Added `.github/workflows/supabase-backup.yml` for scheduled/manual encrypted logical JSON, Auth metadata and private Storage backups. The workflow reads `SUPABASE_SERVICE_ROLE_KEY` and `BACKUP_ENCRYPTION_PASSPHRASE` Actions secrets; the project URL is hard-coded in the workflow. `SUPABASE_DB_URL` and a `SUPABASE_URL` secret are not required by the current workflow.
- Added `scripts/backup_supabase_storage.py` and `scripts/restore_supabase_storage.py` for private object backup and non-overwriting restoration.
- Expanded `BACKUP_GUIDE.md` with secret configuration, checksum/HMAC verification and separate-project recovery steps.
- Updated the README to reflect the implemented ledger and current billing/backup limitations.
- Migrations 017, 018, 019 and 045 are committed to GitHub. The user confirmed migration 017 reconciliation and migration 018 accounting installation/report checks. Migration 019 and the new migration 045 require live Supabase application and functional acceptance tests before relying on gross profit or the new historical/opening/period controls. Migration 045's RPCs are owner/admin/accountant restricted; historical backfill is explicit and does not run automatically on migration.

## Migration 045 — accounting completion workflow\n\n- `backfill_accounting_history(business_id)` posts eligible cloud historical sales, offline sales, purchases, expenses and offline refunds exactly once using unique source keys. Legacy `sales` and `purchases` rows must have `status='posted'`. Offline-only device records must be synchronised first. Historical COGS is posted only when legacy sale-item unit costs or recorded inventory cost movements exist; missing historical cost is deliberately not guessed.\n- `post_accounting_opening_balances(business_id, effective_date, balances_json)` accepts balance-sheet account codes and debit/credit amounts, then balances the opening journal through Owner capital (3000). Only one opening batch is permitted per business. Opening balances must be reconciled to source statements before posting.\n- `reverse_accounting_journal(business_id, journal_id, reversal_date, reason)` creates an equal-and-opposite immutable journal and records the link; the original journal is never edited or deleted.\n- `close_accounting_period(business_id, period_start, period_end)` transfers income/expense balances to retained earnings and locks the closed date range against new journals. Corrections must be recorded in an open period using an authorised reversal. Overlapping closed periods are rejected.\n- These are secured database RPCs, not yet a dedicated visual accounting-workflow screen. Migration 045 must be applied manually in Supabase SQL Editor before the RPCs exist. Do not execute backfill or opening balances until the business, historical data and cutover date have been reviewed.\n\n## Required acceptance tests before calling the platform production-ready

- Two separate business accounts cannot read or mutate each other's data.
- Each role can perform only its permitted actions; denied actions are tested, not just allowed actions.
- A sale, purchase, return, refund, obligation payment, stock adjustment, branch transfer and inventory-cost movement remain correct after refresh and sync retry; the sale COGS journal must match the inventory cost movement.
- Two devices reconnecting after offline work do not duplicate transactions or silently overwrite records.
- A statement import rejects malformed rows, skips duplicate external references, and reports inserted counts.
- A statement line cannot be matched to another business, another bank account, a wrong amount or the wrong debit/credit direction.
- A cashbook entry cannot be reconciled more than once.
- The scheduled backup workflow succeeds with the configured required secrets; the encrypted archive passes checksum and HMAC verification. The latest successful run visible in GitHub was on 10 November 2026 before the current release commit; run it again after this release and retain the artifact outside GitHub.
- A full database and Storage restoration succeeds in a separate Supabase project, including document downloads.
- Subscription plan/pricing, manual payment submission and verification, renewals, cancellation, failed-payment handling and entitlement enforcement are tested before commercial launch. Direct provider checkout must remain clearly marked unavailable until implemented and tested.
- Android and iPhone PWA installation, offline launch, update and theme persistence are verified.

## Release status

The GitHub Actions deployment workflow for the latest dark-mode correction completed successfully. That confirms the repository workflow completed; it is not a substitute for live browser, Supabase or device acceptance testing.

**Current assessment:** strong feature foundation; not yet independently certified for production accounting, disaster recovery or commercial subscription operations. The backup workflow has completed successfully, but the encrypted logical export has not been restored into a separate recovery project. Before commercial launch, finish the accounting acceptance tests, validate opening inventory and balances, test multi-device offline conflict handling and security boundaries, verify Android/iPhone PWA behaviour, and implement direct payment-provider integration only after the provider and commercial pricing model are confirmed.


## Release engineering review — 10 November 2026

Repository checks observed on commit `8a4f3ce37ef07c5111c99320850328ddf6cbf747`:
- GitHub Pages deployment: successful.
- JavaScript syntax validation: successful.
- Browser interaction smoke test: successful on Android-sized and desktop Chromium viewports.
- Android APK build and GitHub Release publication: successful. The current APK is debug-signed, not a Play Store production-signed package.
- Supabase off-site backup: a successful run exists from earlier on 10 November, but it predates the latest release commit. A separate-project restore has not been demonstrated.

The Android wrapper previously loaded the remote GitHub Pages URL even though the workflow packaged the web files into the APK. The production-readiness update changes the wrapper to load its bundled app shell through AndroidX WebViewAssetLoader, so the interface can open without network access; cloud authentication and sync still require connectivity. This is not considered device-verified until the rebuilt APK is installed and tested in airplane mode on a real Android device.

The browser smoke suite now exercises Executive Action Centre, Financial Planning and Plans & Billing navigation, checks the Action Centre panels, and attempts an offline app-shell reload. The CI workflow now checks all root JavaScript files and validates manifest assets and migration filename integrity.

The Supabase security audit SQL is read-only. It reports tables without RLS, RLS-enabled tables without policies, public/anonymous table grants, and SECURITY DEFINER functions without a fixed search_path. Review every result against intended public data and RPC access; a clean report is not a substitute for cross-account tests using two separate authenticated business accounts.

**Remaining release blockers that require live Supabase/device acceptance:** execute the read-only security audit; verify RLS isolation and role-denial cases with separate accounts; verify bank statement reconciliation; apply and test migration 019 if it is not already installed; validate opening inventory and COGS; run and restore an encrypted backup in a separate recovery project; test offline sync conflict recovery across two devices; and test the rebuilt APK offline on Android.