#!/usr/bin/env python3
"""Validate Supabase PostgreSQL credentials, then create a custom-format pg_dump."""
import argparse
import os
import re
import subprocess
from pathlib import Path
from urllib.parse import unquote

def connection():
    raw = os.environ.get("SUPABASE_DB_URL", "").strip()
    if not raw:
        raise SystemExit("SUPABASE_DB_URL is empty.")
    # Parse against the known Supabase pooler hostname rather than urlsplit:
    # urlsplit can reject raw '[' or ']' characters in a password before
    # credentials can be decoded. The greedy password capture ends at the
    # pooler host, so '@' inside a password is also handled.
    pattern = re.compile(
        r"^(postgres(?:ql)?://)([^:/@]+):(.+)@([^/@]+\.pooler\.supabase\.com):(\d+)/([^?#]+)(?:\?[^#]*)?$",
        re.IGNORECASE,
    )
    match = pattern.fullmatch(raw)
    if not match:
        raise SystemExit(
            "Connection URI format is invalid. Copy the complete Supabase Session Pooler URI "
            "including its pooler hostname, port 5432, and /postgres database path."
        )
    scheme, encoded_user, encoded_password, host, port_text, database = match.groups()
    username = unquote(encoded_user)
    password = unquote(encoded_password)
    port = int(port_text)
    database = unquote(database)
    if port != 5432:
        raise SystemExit("Use Session Pooler port 5432 for pg_dump.")
    if not username or not password:
        raise SystemExit("The Session Pooler URI must contain a username and an actual database password.")
    if "[YOUR-PASSWORD]" in password or "YOUR-PASSWORD" in password:
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
