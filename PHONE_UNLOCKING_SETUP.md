# Phone Unlocking — final activation checklist

The application module is already included in `index.html` through `phone-unlocking.js`, and the service worker caches that module. The database migrations are `033_phone_unlocking_services.sql`, `034_mobile_unlock_provider_catalogue.sql`, and `035_phone_unlocking_owner_approval.sql`.

## 1. Install the database objects once

1. Open the Supabase project used by this application.
2. Open **SQL Editor**.
3. Open `supabase/INSTALL_PHONE_UNLOCKING.sql` in this repository, copy its complete contents, paste into a new SQL query, and run it.
4. Confirm the query completes without an error. Do not run the installer repeatedly unless you have reviewed the migration changes.

The installer is business-scoped and applies row-level security. The module is seeded disabled for each business; the owner/admin can enable it in the business workspace.

## 2. Deploy the provider Edge Function

The source is `supabase/functions/mobile-unlock-provider/index.ts`.

Deploy it as a Supabase Edge Function named exactly:

`mobile-unlock-provider`

Use the Supabase Dashboard's **Edge Functions** area to create/deploy the function from the repository source, or deploy it with the Supabase CLI from the repository root:

```sh
supabase functions deploy mobile-unlock-provider --project-ref YOUR_PROJECT_REF
```

## 3. Add the provider secret securely

In Supabase Dashboard → **Edge Functions → Secrets**, add:

- Name: `MOBILE_UNLOCK_API_KEY`
- Value: the API key issued to your own authorised Mobile-Unlock account

Never put this key in `index.html`, `phone-unlocking.js`, GitHub Pages, a public repository, or a customer-facing device. The function reads the secret server-side. Supabase supplies the project URL and anon key to the Edge Function runtime.

## 4. Activate and verify

1. Sign in to the White Lion app and select the correct business.
2. Open the Phone Unlocking & Device Services workspace and enable the module.
3. Add your own customer-facing services and selling prices.
4. Select **Test Mobile-Unlock API connection**. This test must show a verified connection and does not submit an order or spend provider credit.
5. Select **Sync live provider catalogue**. Confirm the service count and provider currency before importing any provider service.
6. Create a low-risk test order using a device you own or are explicitly authorised to service.
7. Record the payment. Provider submission remains blocked until the order is fully paid and explicitly approved by the business owner.

## Important operational safeguards

- Only authorised owner/admin/manager business members can access the sensitive order register and IMEI.
- Only the business owner can approve and submit provider orders.
- The provider key is never sent to the browser.
- An uncertain provider response must be reconciled in the provider dashboard before any retry. Do not submit again just because the first request timed out.
- The module records customer payments and refunds, but the current interface explicitly states that automatic general-ledger journal posting is not yet enabled. Do not treat the module's order totals as posted accounting entries.
- Provider availability, service eligibility, turnaround time, and charges are determined by the provider account and its current catalogue; the software cannot guarantee that a particular IMEI can be unlocked.
