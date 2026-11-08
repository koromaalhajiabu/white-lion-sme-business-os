# White Lion SME Business Operating System

A multi-industry SME operations platform by White Lion Tech Solutions. The frontend is deployed as a static Progressive Web App through GitHub Pages; Supabase provides authentication, cloud data and tenant security.

**Developer:** Designed by Alhaji Abu Koroma  
**Live application:** https://koromaalhajiabu.github.io/white-lion-sme-business-os/  
**Repository:** https://github.com/koromaalhajiabu/white-lion-sme-business-os

## Platform capabilities

- Multi-industry business profiles and workspace membership.
- Sales/POS, products, purchasing, customers, suppliers and expenses.
- Supabase authentication, business membership and row-level security.
- IndexedDB local persistence and offline transaction synchronisation.
- Multi-branch operations, branch access and stock transfers.
- Returns/refunds, cashbook, receivables/payables and financial payment records.
- Barcode, batch/expiry and controlled stock adjustment features.
- Private business document storage.
- Sports and local-league competition management.
- Developer administration and audit logging.
- Responsive PWA shell, install support, service-worker caching and light/dark appearance.

## Technology and deployment

- Frontend: HTML, CSS and JavaScript.
- Hosting: GitHub Pages.
- Cloud: Supabase.
- Local persistence: IndexedDB.
- PWA: Web App Manifest and Service Worker.

Do not add a Supabase service-role key to browser code or the public repository. Only the intended publishable/anon key may be used in the browser, with Row Level Security correctly configured.

## Database setup

SQL migrations are in `supabase/migrations/`. The consolidated operations installer is:

`supabase/INSTALL_ALL_OPERATIONS.sql`

The installer includes the business operations, inventory/finance controls and the bank/mobile-money statement reconciliation foundation. Review the SQL and execute it in the correct Supabase project. A GitHub commit does not execute database migrations automatically.

### Bank and mobile-money reconciliation

Migration 017 adds:
- Business-scoped bank and mobile-money account records.
- Statement-line import through a role-checked RPC.
- Duplicate external-reference protection.
- Matching to cashbook entries with account, amount and debit/credit validation.
- Audit log events for imports and matches.

This is a manual statement import and matching foundation. It does not connect directly to a bank or mobile-money provider, and the full reconciliation interface and general ledger are still future work.

## Important accounting and backup limitations

- The reviewed schema does not yet implement a complete double-entry general ledger, chart of accounts, trial balance or audited financial statements.
- Existing dashboard/report figures are operational summaries. Do not treat net sales less recorded expenses as audited net profit or available cash.
- The browser JSON export is a local-device backup, not a full Supabase backup.
- Supabase database exports and private Storage object files require separate off-site backup and restoration testing.
- Do not use the platform as the sole record of statutory accounts until accounting controls and independent acceptance tests are complete.

## Production readiness

See [PROFESSIONAL_READINESS.md](PROFESSIONAL_READINESS.md) for the feature inventory, known gaps, new migration details and required acceptance tests.

See [BACKUP_GUIDE.md](BACKUP_GUIDE.md) for independent database and private-file backup guidance.

## Local run

Serve the repository over HTTPS or localhost for service-worker and PWA behaviour. Opening the HTML file directly with a `file://` URL does not provide the full PWA experience.
