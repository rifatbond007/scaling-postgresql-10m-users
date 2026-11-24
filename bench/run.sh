#!/usr/bin/env bash
# Usage (inside bench container): /bench/run.sh LABEL CLIENTS THREADS SECONDS "feed.sql@9 write.sql@1" [PORT] [HOST]
# LABEL may be a path like step3/direct_100. Runs a discarded warm-up (30 s), then the measured run; writes logs + summary to raw/LABEL/
set -euo pipefail
LABEL=$1 C=$2 J=$3 T=$4 SCRIPTS=$5 PORT=${6:-5432} HOST=${7:-$PGHOST}
OUT=/raw/$LABEL; rm -rf "$OUT"; mkdir -p "$OUT/txlog"; cd "$OUT"
FARGS=(); NAMES=()
for s in $SCRIPTS; do FARGS+=(-f "/bench/$s"); NAMES+=("${s%%.sql*}"); done

echo "== prewarm cache (indexes into shared_buffers, posts heap into OS cache)"
psql -h "${PGHOST}" -p 5432 -qAt -c "SELECT pg_prewarm('idx_posts_user_created_live'), pg_prewarm('follows_pkey'), pg_prewarm('posts','read');" >/dev/null 2>&1 || echo "prewarm skipped"

echo "== warm-up 30s (discarded)"
pgbench -n -h "$HOST" -p "$PORT" "${FARGS[@]}" -c "$C" -j "$J" -T 30 >/dev/null 2>&1 || true

# reset query stats so they cover only the measured run (always via the real server)
psql -h "${PGHOST}" -p 5432 -qAt -c "SELECT pg_stat_statements_reset();" >/dev/null 2>&1 || true

echo "== measured run: $LABEL c=$C j=$J T=${T}s scripts=[$SCRIPTS]"
pgbench -n -h "$HOST" -p "$PORT" "${FARGS[@]}" -c "$C" -j "$J" -T "$T" -P 10 -r \
  -l --log-prefix="$OUT/txlog/run" > pgbench.out 2> pgbench.err || echo "pgbench exit $?"
grep -E "^(number of (transactions|failed)|latency average|tps)" pgbench.out || true
grep -c "too many clients\|FATAL\|ERROR" pgbench.err | sed "s/^/error lines in stderr: /" || true
python3 /bench/percentiles.py "$OUT/txlog/run" "${NAMES[@]}" | tee percentiles.txt
