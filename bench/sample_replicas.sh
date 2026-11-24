#!/usr/bin/env bash
# Step 4 host-side sampler, every 5 s: CPU/memory of primary and replicas, replication lag, host available RAM.
# Usage: bench/sample_replicas.sh OUTFILE SECONDS
OUT=$1; DUR=$2; END=$((SECONDS + DUR))
echo "time,pg_cpu,pg_mem,r1_cpu,r1_mem,r2_cpu,r2_mem,max_replay_lag_ms,max_lag_bytes,host_avail_mb" > "$OUT"
stat() { docker stats --no-stream --format '{{.CPUPerc}},{{.MemUsage}}' "$1" 2>/dev/null | sed 's| / [^,]*||'; }
while [ $SECONDS -lt $END ]; do
  lag=$(docker exec pg psql -U postgres -d app -Atc "SELECT coalesce(round(max(extract(epoch FROM replay_lag))*1000),0), coalesce(max(pg_wal_lsn_diff(sent_lsn, replay_lsn)),0) FROM pg_stat_replication;" 2>/dev/null | tr '|' ',')
  p=$(stat pg); r1=$(stat replica1); r2=$(stat replica2)
  echo "$(date +%T),${p:-,},${r1:-,},${r2:-,},${lag:-,},$(free -m | awk '/Mem:/{print $7}')" >> "$OUT"
  sleep 5
done
