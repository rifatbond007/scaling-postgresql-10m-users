#!/usr/bin/env bash
# Apply the passwords in .env to the running lab: postgres + replicator roles on the primary,
# primary_conninfo on running replicas, PgBouncer's auth file. Safe to run repeatedly.
set -euo pipefail
cd "$(dirname "$0")/.."
[ -f .env ] || { echo "error: .env missing (run: make env)" >&2; exit 1; }
set -a; . ./.env; set +a
running() { docker ps --format '{{.Names}}' | grep -qx "$1"; }

running pg || { echo "error: pg container is not running (run: make up)" >&2; exit 1; }
docker exec -i pg psql -U postgres -d app -q -v ON_ERROR_STOP=1 -v pw="$POSTGRES_PASSWORD" <<'SQL'
ALTER ROLE postgres PASSWORD :'pw';
SQL
echo "postgres password updated"

docker/replica/setup-primary.sh >/dev/null
echo "replicator password updated"

for r in replica1 replica2; do
  running "$r" || continue
  # the replica stores the replication password in primary_conninfo (written by pg_basebackup -R)
  docker exec -i "$r" psql -U postgres -d app -q -v ON_ERROR_STOP=1 -v pw="$REPLICATOR_PASSWORD" <<'SQL' >/dev/null
SELECT regexp_replace(current_setting('primary_conninfo'), 'password=\S+', 'password=' || :'pw') AS ci \gset
ALTER SYSTEM SET primary_conninfo = :'ci';
SELECT pg_reload_conf();
SQL
  echo "$r primary_conninfo updated"
done

docker/pgbouncer/make-userlist.sh
if running pgbouncer; then docker restart pgbouncer >/dev/null; echo "pgbouncer restarted"; fi
