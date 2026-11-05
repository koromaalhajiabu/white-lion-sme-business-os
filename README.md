# White Lion SME Business Operating System — Starter Build

## Included
- Responsive business dashboard and navigation
- Multi-industry business profile settings
- Products and inventory records
- Sales recording with stock deduction
- Purchase recording with stock increase
- Customer and supplier directories
- Expense tracking
- Basic operational summary
- JSON backup and restore
- Sales CSV export
- IndexedDB local persistence
- Basic PWA manifest and service worker shell

## Run locally
Open `index.html` in a modern browser. For PWA installation and service worker support, serve the folder over HTTPS or localhost.

## Deploy to GitHub Pages
1. Create a repository, for example `white-lion-sme-business-os`.
2. Upload `index.html`, `manifest.webmanifest`, and `sw.js` to the repository root.
3. In GitHub, open Settings → Pages.
4. Select Deploy from a branch, choose `main` and `/root`, then Save.
5. Open the published HTTPS URL in Chrome on Android and use the browser menu → Add to Home screen / Install app.

## Important limitations of this starter build
- Data is stored in the browser on the current device only.
- It is not yet connected to Supabase or a cloud database.
- There is no real multi-user authentication, role enforcement, tenant isolation, cloud sync, payroll, double-entry accounting, tax engine, or audited financial reporting yet.
- Do not use it for live business financial records until cloud security, backup, accounting logic, and data recovery are implemented and tested.
- The service worker caches the application shell; business records persist in IndexedDB. This is not yet a full offline sync engine.

## Branding
Designed by Alhaji Abu Koroma
White Lion Tech Solutions


## Supabase foundation (new)
A first-pass multi-tenant schema is included at:
`supabase/migrations/001_initial_multi_tenant_schema.sql`

It defines:
- Profiles, businesses, business memberships and branches
- Role types: owner, admin, manager, cashier, storekeeper, accountant, viewer
- Customers, suppliers, products and branch-level inventory
- Sales, sale items, purchases, purchase items and inventory movements
- Expenses and audit logs
- Row Level Security policies scoped by business membership
- `create_business(...)` RPC to create a business, owner membership and Main Branch
- `post_sale(...)` RPC to post a sale and deduct stock atomically
- `post_purchase(...)` RPC to receive a purchase and increase stock atomically

### Important before using
This migration is a development foundation, not a production certification. It has not been run against your Supabase project or tested against real user accounts. Review and execute it first in a NEW test Supabase project. Do not put a Supabase service-role key in browser JavaScript. Only the project URL and anon/publishable key belong in a client app, with RLS enabled.

The current HTML starter is still local-first and is not yet wired to these tables or RPCs. The migration therefore does not by itself enable cloud login, cloud sync, or tenant-aware screens. The SQL intentionally prevents direct client inserts into posted sales/purchases and expects the app to call the transaction RPCs. The first accounting iteration still needs a proper double-entry ledger, immutable journal entries, tax handling, returns, refunds, reversals and reconciliation before it can be trusted for live bookkeeping.

### Apply in a test project
1. Create a Supabase project.
2. Open SQL Editor.
3. Paste and run the migration file.
4. Check the Table Editor and Authentication users.
5. Test with two separate user accounts and two businesses.
6. Confirm that each account can only read its own business records.
7. Test `create_business`, `post_sale` and `post_purchase` only with sample data.

Do not enable real customer data until the RLS and transaction tests have passed.
