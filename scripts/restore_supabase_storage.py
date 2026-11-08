#!/usr/bin/env python3
"""Restore backed-up files into an existing Supabase Storage bucket.

Run only against a verified recovery project. Existing object names are never overwritten.
"""
import mimetypes
import os
import urllib.error
import urllib.parse
import urllib.request
from pathlib import Path

base = os.environ["SUPABASE_URL"].rstrip("/")
key = os.environ["SUPABASE_SERVICE_ROLE_KEY"]
bucket = os.environ.get("SUPABASE_BACKUP_BUCKET", "business-documents")
root = Path(os.environ.get("BACKUP_STORAGE_DIR", "backup/storage")) / bucket
if not root.is_dir():
    raise SystemExit(f"Storage backup folder not found: {root}")

headers = {"apikey": key, "Authorization": f"Bearer {key}", "x-upsert": "false"}
files = sorted(p for p in root.rglob("*") if p.is_file())
if not files:
    print("No files found to restore.")
    raise SystemExit(0)

for index, path in enumerate(files, 1):
    object_path = path.relative_to(root).as_posix()
    encoded = urllib.parse.quote(object_path, safe="/")
    url = f"{base}/storage/v1/object/{urllib.parse.quote(bucket, safe='')}/{encoded}"
    mime = mimetypes.guess_type(path.name)[0] or "application/octet-stream"
    req_headers = dict(headers, **{"Content-Type": mime})
    req = urllib.request.Request(url, data=path.read_bytes(), headers=req_headers, method="POST")
    try:
        with urllib.request.urlopen(req, timeout=180) as response:
            response.read()
    except urllib.error.HTTPError as exc:
        detail = exc.read().decode(errors="replace")
        raise SystemExit(
            f"Restore stopped at {object_path} ({exc.code}): {detail}. "
            "No existing objects are overwritten; review the target bucket before retrying."
        ) from exc
    print(f"Restored {index}/{len(files)}: {object_path}")

print(f"Storage restore complete: {len(files)} object(s) restored to {bucket!r}.")
