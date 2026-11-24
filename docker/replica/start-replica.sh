#!/usr/bin/env bash
# Step 4: replica entrypoint. On first start, clone the primary with pg_basebackup
# (-R writes standby.signal + primary_conninfo; -S uses this replica's slot), then run as a hot standby.
set -euo pipefail
export PGDATA=/var/lib/postgresql/data/pgdata
if [ ! -s "$PGDATA/PG_VERSION" ]; then
  until pg_isready -h pg -q; do sleep 1; done
  echo "cloning primary into $PGDATA using slot $SLOT ..."
  PGPASSWORD=lab pg_basebackup -h pg -U replicator -D "$PGDATA" -X stream -R -S "$SLOT" --progress
fi
exec postgres -D "$PGDATA" \
  -c shared_buffers=256MB -c effective_cache_size=768MB -c work_mem=16MB \
  -c max_connections=100 -c shared_preload_libraries=pg_stat_statements -c track_io_timing=on
