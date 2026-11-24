#!/usr/bin/env bash
# Regenerates userlist.txt (SCRAM hash of the postgres user) for PgBouncer. Not committed to git.
# Run after every (re)seed: a new database gives the postgres user a new hash.
set -euo pipefail
cd "$(dirname "$0")"
line=$(docker exec pg psql -U postgres -d app -Atc \
  "SELECT '\"' || rolname || '\" \"' || rolpassword || '\"' FROM pg_authid WHERE rolname='postgres';")
[ -n "$line" ] || { echo "error: got no password hash (is the pg container running?)" >&2; exit 1; }
echo "$line" > userlist.txt
echo "wrote $(pwd)/userlist.txt"
