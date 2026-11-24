#!/usr/bin/env bash
# Step 4: prepare the primary for streaming replication (idempotent).
# The proposal's wal_level=replica, max_wal_senders=10, max_replication_slots=10 and
# hot_standby=on are already Postgres 16 defaults, so only these are needed:
set -euo pipefail
cd "$(dirname "$0")/../.."
[ -f .env ] || { echo "error: .env missing (run: make env)" >&2; exit 1; }
set -a; . ./.env; set +a
# 1. replication user
# (password passed as a psql variable, so it never appears in the command line or this file)
docker exec -i pg psql -U postgres -d app -q -v pw="$REPLICATOR_PASSWORD" <<'SQL'
SELECT NOT EXISTS (SELECT FROM pg_roles WHERE rolname = 'replicator') AS missing \gset
\if :missing
  CREATE ROLE replicator WITH REPLICATION LOGIN;
\endif
ALTER ROLE replicator PASSWORD :'pw';
SQL
# 2. allow replication connections from the Docker network (the image only allows them locally)
docker exec pg bash -c "grep -q '^host replication replicator' \$PGDATA/pg_hba.conf || \
  echo 'host replication replicator all scram-sha-256' >> \$PGDATA/pg_hba.conf"
# 3. one physical slot per replica, so the primary keeps WAL a lagging replica still needs,
#    capped so a dead replica can't fill the primary's disk (proposal's warning)
docker exec pg psql -U postgres -d app -qc "ALTER SYSTEM SET max_slot_wal_keep_size = '4GB';"
for s in replica1_slot replica2_slot; do
  docker exec pg psql -U postgres -d app -qAtc \
    "SELECT pg_create_physical_replication_slot('$s') WHERE NOT EXISTS (SELECT FROM pg_replication_slots WHERE slot_name='$s');" >/dev/null
done
docker exec pg psql -U postgres -d app -qAtc "SELECT pg_reload_conf();" >/dev/null
docker exec pg psql -U postgres -d app -c "SELECT slot_name, active FROM pg_replication_slots ORDER BY 1;"
