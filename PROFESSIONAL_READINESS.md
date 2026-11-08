# White Lion SME Business Operating System — Professional Readiness Review

Last reviewed: 8 November 2026

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

1. **A first double-entry ledger foundation is now implemented in migration 018.** It adds a chart of accounts, balanced immutable journal posting, source triggers for new cloud-synced sales/purchases/expenses/returns and obligation payments, manual journals, trial balance, income statement, balance sheet and cash-flow reports. This is not an audited accounting package: historical records are not backfilled, manual cashbook entries are not automatically journaled, new synced stock-managed sales now post COGS using moving weighted-average cost; purchases, batch receipts, approved stock adjustments and branch transfers update branch-level inventory valuation. Existing stock opens at tracked batch costs where available, otherwise product.cost_price. Historical sales are not backfilled, and opening balances and period close/reversals still need a controlled workflow. The existing reports correctly label the operating balance as indicative rather than audited profit.
2. **Bank/mobile-money reconciliation was missing.** Migration 017 now adds a secure foundation for finance users to create bank/mobile-money accounts, import statement rows through an RPC, and match statement lines to cashbook entries. The operations control centre now includes a CSV import and matching interface. This is manual statement import; it is not a direct bank API connection. The interface still needs live Supabase and device acceptance testing.
3. **Backup is not a full cloud backup.** The browser JSON backup covers local IndexedDB records. Supabase database exports and private Storage object bytes still need separate off-site backup and tested restoration.
4. **Offline conflict handling needs real multi-device tests.** Idempotent sync receipts exist, but test simultaneous edits, duplicate retries, partial network loss, device replacement and conflict recovery.
5. **Financial reports are operational summaries, not audited accounts.** Do not represent the current net sales less recorded expenses figure as net profit or available cash.
6. **Production security needs independent verification.** Test cross-business isolation with separate accounts, role escalation attempts, branch scoping, storage access, account recovery and audit coverage.
7. **Mobile/PWA quality needs device testing.** Test install/update behaviour, offline launch, theme persistence, navigation, forms, keyboard handling, printing and small-screen tables on Android and iPhone.

## New changes in this release

- Added `supabase/migrations/018_double_entry_general_ledger.sql` and included it in `supabase/INSTALL_ALL_OPERATIONS.sql`.
- Added `supabase/migrations/019_weighted_average_inventory_cogs.sql` and included it in the consolidated installer.
- Added a finance UI for chart-of-accounts setup, trial balance, Profit & Loss, Balance Sheet, cash-flow reporting and balanced manual journal posting.
- The ledger is designed to post new synced sales, purchases, expenses, returns and receivable/payable payments. Cash sales are routed to cash/bank; credit sales are routed to receivables. Historical records are not automatically rewritten.
- Migration 019 adds branch-level moving weighted-average inventory valuation, cost movement history, automatic COGS and inventory relief for new stock-managed synced sales, plus purchase, batch receipt, approved adjustment and branch-transfer valuation updates. Opening stock is valued using available batch costs and product.cost_price for unbatched quantities. Historical sales are not rewritten; historical COGS is not backfilled. Verify opening values before relying on gross profit.
- Manual cashbook entries are not automatically posted to the ledger in this release to avoid double-counting with existing payment workflows.
- Added `supabase/migrations/017_bank_mobile_money_reconciliation.sql`.
- Added the same migration to `supabase/INSTALL_ALL_OPERATIONS.sql` so the operations installer includes the new reconciliation schema and RPCs.
- Added a finance-only reconciliation interface to the Operations Control Centre: account setup, CSV statement import, unmatched-line review and guarded matching to cashbook entries.
- Linked new cashbook entries to a selected bank/mobile-money account so they can be reconciled later.
- Migrations 017 and 018 are committed to GitHub. Migration 017 was applied and its reconciliation flow was smoke-tested by the user. Migration 018 has **not** yet been executed against Supabase. Run migration 018 alone in the SQL Editor, then verify the objects and reports before posting live accounting transactions.

## Required acceptance tests before calling the platform production-ready

- Two separate business accounts cannot read or mutate each other's data.
- Each role can perform only its permitted actions; denied actions are tested, not just allowed actions.
- A sale, purchase, return, refund, obligation payment and stock adjustment remain correct after refresh and sync retry.
- Two devices reconnecting after offline work do not duplicate transactions or silently overwrite records.
- A statement import rejects malformed rows, skips duplicate external references, and reports inserted counts.
- A statement line cannot be matched to another business, another bank account, a wrong amount or the wrong debit/credit direction.
- A cashbook entry cannot be reconciled more than once.
- A full backup and restoration are tested in a separate Supabase project, including Storage objects.
- Android and iPhone PWA installation, offline launch, update and theme persistence are verified.

## Release status

The GitHub Actions deployment workflow for the latest dark-mode correction completed successfully. That confirms the repository workflow completed; it is not a substitute for live browser, Supabase or device acceptance testing.

**Current assessment:** strong feature foundation; not yet independently certified for production accounting or disaster recovery. Next work: apply and verify migration 019, test weighted-average inventory valuation and COGS with controlled demo purchases/sales, reconcile the opening inventory value, then implement controlled historical migration, opening balances and period closing before treating the statements as complete.
