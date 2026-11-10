# White Lion SME — automated logical backup and recovery

## What the automated backup contains

The workflow `.github/workflows/supabase-backup.yml` runs manually or daily at 02:30 UTC. It no longer uses a PostgreSQL password or `SUPABASE_DB_URL`.

It uses the Supabase service-role API to export:
- Every readable public REST resource exposed by the project's PostgREST OpenAPI document, as paginated JSON files.
- Supabase Auth user metadata returned by the Auth admin API (not passwords, MFA secrets, active sessions, or provider secrets).
- Every object in the private `business-documents` Storage bucket.
- The SQL migration files committed in this repository.

The workflow encrypts the collected files before uploading an artifact to GitHub Actions. Artifacts are retained for 30 days. Download successful artifacts periodically and keep encrypted copies in a separate secure location.

**Important limitation:** this is a logical JSON/data-and-migrations backup, not a full PostgreSQL physical or custom-format dump. It does not automatically capture live database objects that are absent from the repository migrations, Supabase project settings, Edge Function secrets, Auth passwords/MFA/session state, or Storage bucket configuration/policies unless those are represented in the archived migrations. A separate recovery-project restore and validation is required before calling disaster recovery complete.

## One-time GitHub configuration

Open:
https://github.com/koromaalhajiabu/white-lion-sme-business-os/settings/secrets/actions

Required Actions secrets (the current workflow reads exactly these two):
1. `SUPABASE_SERVICE_ROLE_KEY` — service-role key for this project. It is used only inside the GitHub-hosted runner; never put it in frontend code or repository files.
2. `BACKUP_ENCRYPTION_PASSPHRASE` — a long, unique passphrase. Store it securely; without it, artifacts cannot be decrypted.

The project URL (`https://nclncqlgnxnijlumznnt.supabase.co`) is currently set directly in `.github/workflows/supabase-backup.yml`, so a `SUPABASE_URL` secret is not required. `SUPABASE_DB_URL` is not used by this REST logical-backup workflow.

Open Actions → **Supabase off-site backup** → **Run workflow**. A successful run and artifact are required before considering the scheduled backup operational.

## Restore and recovery

Always restore into a separate recovery Supabase project first. Never test restoration over the live production database.

1. Download the encrypted artifact from a successful workflow run.
2. Verify its checksum with `sha256sum -c white-lion-supabase-backup.tar.gz.enc.sha256`.
3. Verify its HMAC before decrypting:
   ```bash
   expected=$(awk '{print $2}' white-lion-supabase-backup.tar.gz.enc.hmac)
   actual=$(openssl dgst -sha256 -hmac "$BACKUP_ENCRYPTION_PASSPHRASE" white-lion-supabase-backup.tar.gz.enc | awk '{print $2}')
   test "$actual" = "$expected" || { echo "Backup authentication failed"; exit 1; }
   ```
4. Decrypt and extract:
   ```bash
   openssl enc -d -aes-256-cbc -pbkdf2 -iter 600000 \
     -in white-lion-supabase-backup.tar.gz.enc \
     -out white-lion-supabase-backup.tar.gz \
     -pass env:BACKUP_ENCRYPTION_PASSPHRASE
   tar -xzf white-lion-supabase-backup.tar.gz
   ```
5. Apply the archived SQL migrations to a fresh recovery project in their numbered order, reviewing any project-specific prerequisites before running them.
6. Restore each JSON table file from `backup/data/tables/` using the recovery project's service-role REST API. Use dependency-aware ordering and upsert by each table's primary key; do not blindly insert duplicate rows. Review tables without primary keys manually.
7. Recreate Auth users using the Auth Admin API from `backup/data/AUTH_USERS.json`. Users may need password resets and provider/MFA reconfiguration because credentials and MFA/session secrets are not exported.
8. Create the private `business-documents` bucket and its policies in the recovery project, then run `scripts/restore_supabase_storage.py` with the recovery project's URL and service-role key. The utility does not overwrite existing object names.
9. Verify business records, membership, RLS, roles, accounting reports, inventory, branch records, Auth login, and document downloads in the recovery project. Record the date and outcome.

The JSON export and repository migrations are recovery inputs, not proof of a successful restore. Do not claim disaster recovery is complete until a separate-project restore is tested.

## Security and retention

- Never put a service-role key or database password in browser code, GitHub source files, screenshots or chat.
- Keep the encryption passphrase separate from downloaded artifacts.
- Limit access to repository Actions artifacts and secrets.
- Retain encrypted copies outside GitHub; Actions artifacts expire after 30 days.
- Rotate any secret that has ever been exposed.

## Existing browser backup limitation

The app's JSON export covers only IndexedDB records on the current device. Document-list export is metadata only. Neither replaces this cloud logical export.
