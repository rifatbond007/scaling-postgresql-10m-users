#!/usr/bin/env bash
# Regenerates userlist.txt (SCRAM hash of the postgres user) for PgBouncer. Not committed to git.
cd "$(dirname "$0")"
docker exec pg psql -U postgres -d app -Atc \
  "SELECT '\"' || rolname || '\" \"' || rolpassword || '\"' FROM pg_authid WHERE rolname='postgres';" > userlist.txt
echo "wrote $(pwd)/userlist.txt"
