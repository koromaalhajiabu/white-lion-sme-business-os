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
- Developer administration, account controls and business/platform audit logging.
- English, French, Arabic (RTL), Spanish, Hindi and Simplified Chinese language options.
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

This is a legacy operations installer, not a complete installer for every migration in the repository. Review each later numbered migration and apply it only when its prerequisites and current project state have been checked.

The installer includes the business operations, inventory/finance controls and the bank/mobile-money statement reconciliation foundation. Review the SQL and execute it in the correct Supabase project. A GitHub commit does not execute database migrations automatically.

### Bank and mobile-money reconciliation

Migration 017 adds:
- Business-scoped bank and mobile-money account records.
- Statement-line import through a role-checked RPC.
- Duplicate external-reference protection.
- Matching to cashbook entries with account, amount and debit/credit validation.
- Audit log events for imports and matches.

This is a manual statement import and matching foundation. It does not connect directly to a bank or mobile-money provider. Migration 017 must be installed for the reconciliation screen.

## Accounting, security and backup limitations

- Migrations 018 and 019 provide the double-entry ledger, chart of accounts, balanced journals, trial balance, Profit & Loss, Balance Sheet, cash-flow reporting, moving weighted-average stock valuation and COGS posting foundation. Historical sales are not backfilled; opening balances and controlled period close/reversal workflows still require further work and acceptance testing.
- Existing operational dashboard totals are not audited net profit or available cash. Do not use the platform as the sole statutory accounting record until independent accounting acceptance tests are complete.
- The browser JSON export is a local-device backup, not a full Supabase backup.
- A scheduled database + private Storage backup workflow is now in `.github/workflows/supabase-backup.yml`. It requires the documented GitHub Actions secrets, and a full recovery test in a separate Supabase project is still required.
- Subscription plans, business trials, invoice records, payment submissions and administrator verification are present in the repository migrations and billing interface. Payments are manually submitted and verified; direct Orange Money/AfriMoney/bank API checkout, automated recurring collection and independent end-to-end billing acceptance remain outstanding. Do not advertise automatic provider integration.

## Production readiness

Run the read-only [production security audit](supabase/PRODUCTION_SECURITY_AUDIT.sql) in the Supabase SQL Editor before launch. It reports RLS coverage, public grants and SECURITY DEFINER functions for review; it does not modify data or certify tenant isolation.

See [PROFESSIONAL_READINESS.md](PROFESSIONAL_READINESS.md) for the feature inventory, known gaps, new migration details and required acceptance tests.

See [BACKUP_GUIDE.md](BACKUP_GUIDE.md) for GitHub Actions secret setup, encrypted backups, integrity checks and recovery instructions.

## Local run

Serve the repository over HTTPS or localhost for service-worker and PWA behaviour. Opening the HTML file directly with a `file://` URL does not provide the full PWA experience.
