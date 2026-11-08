#!/usr/bin/env python3
"""Download every object in a private Supabase Storage bucket for off-site backup."""
import json
import os
import sys
import urllib.error
import urllib.parse
import urllib.request
from pathlib import Path

base = os.environ["SUPABASE_URL"].rstrip("/")
key = os.environ["SUPABASE_SERVICE_ROLE_KEY"]
bucket = os.environ.get("SUPABASE_BACKUP_BUCKET", "business-documents")
root = Path(os.environ.get("BACKUP_STORAGE_DIR", "backup/storage")) / bucket
root.mkdir(parents=True, exist_ok=True)
headers = {"apikey": key, "Authorization": f"Bearer {key}", "Content-Type": "application/json"}

def request_json(url, payload=None):
    data = None if payload is None else json.dumps(payload).encode()
    req = urllib.request.Request(url, data=data, headers=headers, method="GET" if payload is None else "POST")
    try:
        with urllib.request.urlopen(req, timeout=90) as response:
            return json.loads(response.read().decode())
    except urllib.error.HTTPError as exc:
        detail = exc.read().decode(errors="replace")
        raise RuntimeError(f"Supabase Storage request failed ({exc.code}): {detail}") from exc

def download_object(object_path):
    encoded = urllib.parse.quote(object_path, safe="/")
    url = f"{base}/storage/v1/object/{urllib.parse.quote(bucket, safe='')}/{encoded}"
    req = urllib.request.Request(url, headers={"apikey": key, "Authorization": f"Bearer {key}"})
    destination = root / object_path
    destination.parent.mkdir(parents=True, exist_ok=True)
    try:
        with urllib.request.urlopen(req, timeout=180) as response, destination.open("wb") as output:
            while True:
                chunk = response.read(1024 * 1024)
                if not chunk:
                    break
                output.write(chunk)
    except urllib.error.HTTPError as exc:
        detail = exc.read().decode(errors="replace")
        raise RuntimeError(f"Could not download {object_path} ({exc.code}): {detail}") from exc

count = 0
def walk(prefix=""):
    global count
    offset = 0
    while True:
        rows = request_json(
            f"{base}/storage/v1/object/list/{urllib.parse.quote(bucket, safe='')}",
            {"prefix": prefix, "limit": 100, "offset": offset, "sortBy": {"column": "name", "order": "asc"}},
        )
        if not isinstance(rows, list):
            raise RuntimeError(f"Unexpected Storage listing for prefix {prefix!r}: {rows!r}")
        for item in rows:
            name = item.get("name")
            if not name or name in (".", ".."):
                continue
            path = f"{prefix}/{name}" if prefix else name
            if item.get("id") is None and item.get("metadata") is None:
                walk(path)
            else:
                download_object(path)
                count += 1
                print(f"Backed up {count} object(s): {path}")
        if len(rows) < 100:
            break
        offset += len(rows)

walk()
print(f"Storage backup complete: {count} object(s) from bucket {bucket!r}.")
