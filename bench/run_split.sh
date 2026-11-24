#!/usr/bin/env bash
# Step 4 (inside bench container): reads and writes as two separate pgbench runs, so reads can go
# to other hosts than writes. Writes: 4 clients at a fixed rate on the primary. Reads: closed loop (as fast as possible).
# Usage: /bench/run_split.sh LABEL READ_CLIENTS "READ_HOSTS" WRITES_PER_SEC SECONDS
#   READ_HOSTS e.g. "pg" (1 node) or "replica1,replica2" (libpq picks one at random per connection)
set -euo pipefail
LABEL=$1 RC=$2 RHOSTS=$3 WRATE=$4 T=$5
OUT=/raw/$LABEL; rm -rf "$OUT"; mkdir -p "$OUT/txlog"; cd "$OUT"
export PGLOADBALANCEHOSTS=random          # libpq 16: spread connections over the listed hosts
# prewarm: indexes everywhere; the 1.4 GB posts table only on the primary (it can't fit in a 1 GB replica)
IDX="SELECT pg_prewarm('idx_posts_user_created_live'), pg_prewarm('follows_pkey')"
echo "== prewarm"
psql -h pg -qAt -c "$IDX, pg_prewarm('posts','read');" >/dev/null 2>&1 || echo "prewarm skipped on pg"
for h in ${RHOSTS//,/ }; do [ "$h" = pg ] || psql -h "$h" -qAt -c "$IDX;" >/dev/null 2>&1 || echo "prewarm skipped on $h"; done

reads()  { pgbench -n -h "$RHOSTS" -f /bench/feed_lateral.sql -c "$RC" -j 4 "$@"; }
writes() { pgbench -n -h pg -f /bench/write.sql -c 4 -j 2 -R "$WRATE" "$@"; }

echo "== warm-up 30s (discarded)"
writes -T 30 >/dev/null 2>&1 & reads -T 30 >/dev/null 2>&1 || true; wait || true

echo "== measured run: $LABEL reads: $RC clients on [$RHOSTS]; writes: $WRATE/s on pg; ${T}s"
writes -T "$T" -l --log-prefix="$OUT/txlog/writes" > writes.out 2> writes.err &
WP=$!
reads -T "$T" -P 10 -l --log-prefix="$OUT/txlog/reads" > reads.out 2> reads.err || echo "reads pgbench exit $?"
wait $WP || echo "writes pgbench exit $?"
{ echo "reads:  $(grep -E '^tps' reads.out)  $(grep -E 'failed transactions' reads.out)"
  echo "writes: $(grep -E '^tps' writes.out)  $(grep -E 'failed transactions' writes.out)"
  python3 /bench/percentiles.py "$OUT/txlog/reads" feed | tail -1
  python3 /bench/percentiles.py "$OUT/txlog/writes" write | tail -1
  # with -R, pgbench latency includes time spent behind schedule (column 7); real time = col3 - col7
  cat "$OUT"/txlog/writes.* | awk '{print ($3-$7)/1000}' | sort -n | \
    awk '{a[NR]=$1} END{printf "write real time (excl. schedule lag): p50=%.2f p95=%.2f p99=%.2f ms\n", a[int(NR*.5)], a[int(NR*.95)], a[int(NR*.99)]}'
  echo "writes $(grep 'schedule lag' writes.out)"; } | tee summary.txt
