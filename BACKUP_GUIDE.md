# White Lion SME — private documents, automated backup and recovery

## Private document storage
The `business-documents` Supabase Storage bucket is private. Each business uses its UUID as its top-level folder. The app supports PDF, JPEG, PNG and WEBP files up to 50 MB. Active business members can read and upload within their workspace; only owners and administrators can delete. Downloads use short-lived signed links.

## Automated backup workflow
The repository now includes `.github/workflows/supabase-backup.yml`. It can run manually from GitHub Actions or every day at 02:30 UTC. It backs up:
- The Supabase PostgreSQL database using `pg_dump` custom format.
- The actual objects in the private `business-documents` Storage bucket.

The workflow encrypts the combined backup before uploading it as a GitHub Actions artifact. Artifacts are retained for 30 days. This is a useful scheduled recovery copy, but it is not a permanent independent archive: download successful backups periodically and retain encrypted copies in a separate secure location.

### One-time GitHub configuration
Open the repository settings:
https://github.com/koromaalhajiabu/white-lion-sme-business-os/settings/secrets/actions

Add these four **Actions secrets** (never commit them to a file):
1. `SUPABASE_DB_URL` — the database connection string for the intended Supabase project. Use the direct or session-pooler connection string shown by Supabase, with the correct database password.
2. `SUPABASE_URL` — `https://nclncqlgnxnijlumznnt.supabase.co`.
3. `SUPABASE_SERVICE_ROLE_KEY` — the project's service-role key. This key is used only inside the GitHub-hosted backup runner; never place it in frontend code or public repository files.
4. `BACKUP_ENCRYPTION_PASSPHRASE` — a long, unique passphrase. Store it in a password manager. Without it, encrypted backups cannot be decrypted.

Then open Actions → **Supabase off-site backup** → **Run workflow**. Confirm the run succeeds and that the artifact contains the encrypted archive, checksum and HMAC signature. A successful workflow run is the first proof that backup configuration works; it does not prove restoration until the restore test below succeeds.

## Restore procedure
Always restore into a separate recovery Supabase project first. Never test restoration over the live production database.

1. Download the encrypted artifact from a successful workflow run.
2. Verify its checksum with `sha256sum -c white-lion-supabase-backup.tar.gz.enc.sha256`.
3. Set `BACKUP_ENCRYPTION_PASSPHRASE` to the same passphrase, then verify the HMAC before decrypting:
   ```bash
   expected=$(awk '{print $2}' white-lion-supabase-backup.tar.gz.enc.hmac)
   actual=$(openssl dgst -sha256 -hmac "$BACKUP_ENCRYPTION_PASSPHRASE" white-lion-supabase-backup.tar.gz.enc | awk '{print $2}')
   test "$actual" = "$expected" || { echo "Backup authentication failed"; exit 1; }
   ```
4. Decrypt it using the same passphrase:
   ```bash
   openssl enc -d -aes-256-cbc -pbkdf2 -iter 600000 \
     -in white-lion-supabase-backup.tar.gz.enc \
     -out white-lion-supabase-backup.tar.gz \
     -pass env:BACKUP_ENCRYPTION_PASSPHRASE
   tar -xzf white-lion-supabase-backup.tar.gz
   ```
5. Restore the database dump to the recovery project's database:
   ```bash
   pg_restore --no-owner --no-privileges \
     --dbname="$RECOVERY_SUPABASE_DB_URL" \
     backup/database/white-lion-*.dump
   ```
6. Create the private `business-documents` bucket in the recovery project, then run `scripts/restore_supabase_storage.py` with `SUPABASE_URL`, `SUPABASE_SERVICE_ROLE_KEY`, and `SUPABASE_BACKUP_BUCKET=business-documents` set to the recovery project. The restore utility never overwrites existing object names; resolve conflicts deliberately before retrying.
7. Verify users/authentication configuration, business records, row-level security, Storage policies and document downloads in the recovery project. Record the date and result of the test.

Database restore may require project-specific extension, role, or Supabase-managed schema adjustments. Review restore output rather than assuming a zero-error restore. Auth secrets and external provider configuration may need to be reconfigured in the recovery project.

## Existing browser backup limitation
The app's JSON export covers only IndexedDB records on the current device. The document-list export is metadata only. Neither replaces the cloud database and Storage backup above.

## Security rules
- Never place a service-role key or database password in browser code, GitHub source files, screenshots or chat.
- Keep the encryption passphrase separate from downloaded backup artifacts.
- Limit who can read repository Actions artifacts and repository secrets.
- Rotate any secret that has ever been exposed.
- Retain additional encrypted copies outside GitHub; the workflow artifact expires after 30 days.

## Staged acceptance checks
- Test cross-business data isolation with two separate accounts.
- Test role-denied actions as well as permitted actions.
- Test upload, refresh, signed download and owner/admin deletion of documents.
- Run the scheduled/manual backup and perform a complete restore in a separate Supabase project.
- Verify Android Chrome and iPhone Safari/PWA installation, offline launch, sync and printing.
