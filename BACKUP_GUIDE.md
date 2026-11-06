# White Lion SME — document storage and backup guide

## Private document storage
The `business-documents` Supabase Storage bucket is private. Each business uses its UUID as its top-level folder. The app supports PDF, JPEG, PNG and WEBP files up to 50 MB. Active business members can read and upload within their workspace; only owners and administrators can delete. Downloads use short-lived signed links.

## Apply migration 015
In Supabase SQL Editor for project `nclncqlgnxnijlumznnt`, run the complete file `supabase/migrations/015_private_business_document_storage.sql`. Confirm in Dashboard → Storage that `business-documents` exists and is private.

## Backup warning and routine
The existing app JSON export contains records in the current browser's IndexedDB only. The document-list export is metadata only. Neither is a full cloud backup.
- Regularly export the Supabase database using the supported Supabase backup/export workflow and store it outside the project.
- Separately copy the actual objects from the private `business-documents` Storage bucket. A database dump does not contain Storage object bytes.
- Keep an encrypted off-site copy and periodically test restoration in a separate project.
- Supabase Free has no automatic backups; manual/off-site backup is essential.
- Never put a service-role key in browser code, Bolt, GitHub Pages, or a public repository.

## Staged deployment checks
Apply migration 015, deploy this branch to a separate test URL, and test with two separate business accounts: cross-business isolation, upload, refresh, download, owner/admin deletion, and Android Chrome. Merge to main only after all tests pass.
