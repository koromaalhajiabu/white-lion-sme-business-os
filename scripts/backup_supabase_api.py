#!/usr/bin/env python3
"""Export Supabase public REST resources and Auth user metadata using the service-role API.

This is a logical JSON export, not a PostgreSQL physical/custom-format dump.
Database schema and migrations are archived from the checked-out repository separately.
"""
import json
import os
import sys
import time
import urllib.error
import urllib.parse
import urllib.request
from datetime import datetime, timezone
from pathlib import Path

BASE = os.environ["SUPABASE_URL"].rstrip("/")
KEY = os.environ["SUPABASE_SERVICE_ROLE_KEY"]
OUT = Path(os.environ.get("BACKUP_DATA_DIR", "backup/data"))
OUT.mkdir(parents=True, exist_ok=True)
HEADERS = {"apikey": KEY, "Authorization": f"Bearer {KEY}", "Accept": "application/json"}

def get_json(url, headers=None):
    req = urllib.request.Request(url, headers={**HEADERS, **(headers or {})})
    try:
        with urllib.request.urlopen(req, timeout=120) as response:
            return json.loads(response.read().decode("utf-8"))
    except urllib.error.HTTPError as exc:
        detail = exc.read(2000).decode(errors="replace")
        raise RuntimeError(f"Supabase API request failed ({exc.code}) for {url.split('?')[0]}: {detail}") from exc

def write_json(path, value):
    path.parent.mkdir(parents=True, exist_ok=True)
    with path.open("w", encoding="utf-8") as f:
        json.dump(value, f, ensure_ascii=False, indent=2, default=str)
        f.write("\n")

def export_rest_resources():
    spec = get_json(f"{BASE}/rest/v1/")
    paths = spec.get("paths", {})
    resources = []
    for path, methods in paths.items():
        if not path.startswith("/") or path == "/" or path.startswith("/rpc/"):
            continue
        if "get" not in methods:
            continue
        resource = urllib.parse.unquote(path.lstrip("/")).split("/")[0]
        if resource and resource not in resources:
            resources.append(resource)
    if not resources:
        raise RuntimeError("Supabase REST OpenAPI document returned no readable public resources; refusing to create an empty data backup.")
    manifest = []
    for resource in sorted(resources):
        rows = []
        offset = 0
        page_size = 500
        while True:
            query = urllib.parse.urlencode({"select": "*", "limit": page_size, "offset": offset})
            url = f"{BASE}/rest/v1/{urllib.parse.quote(resource, safe='')}?{query}"
            batch = get_json(url)
            if not isinstance(batch, list):
                raise RuntimeError(f"Unexpected response for REST resource {resource!r}; expected an array.")
            rows.extend(batch)
            if len(batch) < page_size:
                break
            offset += len(batch)
        write_json(OUT / "tables" / f"{resource}.json", rows)
        manifest.append({"resource": resource, "rows": len(rows), "file": f"tables/{resource}.json"})
        print(f"Exported {resource}: {len(rows)} row(s)")
    write_json(OUT / "REST_EXPORT_MANIFEST.json", {
        "created_at": datetime.now(timezone.utc).isoformat(),
        "resource_count": len(manifest),
        "resources": manifest,
    })

def export_auth_users():
    users = []
    page = 1
    per_page = 1000
    while True:
        url = f"{BASE}/auth/v1/admin/users?page={page}&per_page={per_page}"
        payload = get_json(url)
        batch = payload.get("users", []) if isinstance(payload, dict) else []
        users.extend(batch)
        if len(batch) < per_page:
            break
        page += 1
    write_json(OUT / "AUTH_USERS.json", users)
    print(f"Exported Auth user metadata: {len(users)} user(s)")

if __name__ == "__main__":
    export_rest_resources()
    export_auth_users()
