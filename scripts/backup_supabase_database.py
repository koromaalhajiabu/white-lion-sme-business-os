#!/usr/bin/env python3
"""Validate Supabase PostgreSQL credentials, then create a custom-format pg_dump."""
import argparse
import os
import subprocess
from pathlib import Path
from urllib.parse import unquote, urlsplit

PROJECT_REF = "nclncqlgnxnijlumznnt"

def connection():
    raw = os.environ.get("SUPABASE_DB_URL", "").strip()
    if not raw:
        raise SystemExit("SUPABASE_DB_URL is empty.")
    try:
        parsed = urlsplit(raw)
        host = parsed.hostname or ""
        port = parsed.port or 5432
    except ValueError:
        raise SystemExit("SUPABASE_DB_URL is malformed. Copy the Session Pooler URI from Supabase Connect.")
    if parsed.scheme not in ("postgres", "postgresql"):
        raise SystemExit("SUPABASE_DB_URL must start with postgres:// or postgresql://.")
    if not host.endswith(".pooler.supabase.com"):
        raise SystemExit("Use the Supabase Session Pooler hostname, not the direct database hostname.")
    if port != 5432:
        raise SystemExit("Use Session Pooler port 5432 for pg_dump.")
    username = unquote(parsed.username or "")
    password = unquote(parsed.password or "")
    database = unquote(parsed.path.lstrip("/")) or "postgres"
    if not username or not password:
        raise SystemExit("The Session Pooler URI must contain a username and an actual database password.")
    if "[YOUR-PASSWORD]" in raw or "YOUR-PASSWORD" in raw:
        raise SystemExit("The database URI still contains the password placeholder.")
    env = os.environ.copy()
    env["PGPASSWORD"] = password
    env["PGSSLMODE"] = "require"
    return host, port, username, database, env

def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--test", action="store_true")
    parser.add_argument("--dump")
    args = parser.parse_args()
    if not args.test and not args.dump:
        parser.error("choose --test or --dump")
    host, port, username, database, env = connection()
    common = ["--host", host, "--port", str(port), "--username", username, "--dbname", database, "--no-password"]
    if args.test:
        print(f"Testing PostgreSQL authentication against {host}:{port} (database: {database})...")
        subprocess.run(
            ["psql", *common, "--no-psqlrc", "--tuples-only", "--command",
             "SELECT current_user, current_database(), now();"],
            env=env, check=True,
        )
        print("Database authentication and SQL query succeeded.")
    else:
        destination = Path(args.dump)
        destination.parent.mkdir(parents=True, exist_ok=True)
        print(f"Exporting database from {host}:{port} to {destination.name}...")
        subprocess.run(
            ["pg_dump", *common, "--format=custom", "--compress=6",
             "--no-owner", "--no-privileges", f"--file={destination}"],
            env=env, check=True,
        )
        subprocess.run(["pg_restore", "--list", str(destination)], env=env,
                       check=True, stdout=subprocess.DEVNULL)
        print(f"Database dump created and validated ({destination.stat().st_size} bytes).")

if __name__ == "__main__":
    main()
