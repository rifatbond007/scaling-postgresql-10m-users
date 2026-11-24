#!/usr/bin/env bash
# Host-side sampler, every 5 s: server connections, container CPU/memory, host available RAM,
# PgBouncer SHOW POOLS, and what active backends wait on. Counts exclude the sampler's own connection.
# Usage: bench/sample.sh OUTFILE SECONDS
OUT=$1; DUR=$2; END=$((SECONDS + DUR))
echo "time,server_conns,active,pg_cpu,pg_mem,pgb_cpu,pgb_mem,host_avail_mb,cl_active,cl_waiting,sv_active,maxwait_ms,wait_io,wait_lock,on_cpu" > "$OUT"
while [ $SECONDS -lt $END ]; do
  c=$(docker exec pg psql -U postgres -d app -Atc "SELECT count(*), count(*) FILTER (WHERE state='active') FROM pg_stat_activity WHERE backend_type='client backend' AND datname='app' AND pid<>pg_backend_pid();" 2>/dev/null | tr '|' ',')
  pg=$(docker stats --no-stream --format '{{.CPUPerc}},{{.MemUsage}}' pg 2>/dev/null | sed 's| / [^,]*||')
  pgb=$(docker stats --no-stream --format '{{.CPUPerc}},{{.MemUsage}}' pgbouncer 2>/dev/null | sed 's| / [^,]*||'); pgb=${pgb:-,}
  avail=$(free -m | awk '/Mem:/{print $7}')
  # what active backends are doing: waiting on disk (IO), on locks (Lock/LWLock), or running (no wait event = CPU)
  waits=$(docker exec pg psql -U postgres -d app -Atc "SELECT count(*) FILTER (WHERE wait_event_type='IO'), count(*) FILTER (WHERE wait_event_type IN ('Lock','LWLock')), count(*) FILTER (WHERE wait_event_type IS NULL) FROM pg_stat_activity WHERE backend_type='client backend' AND state='active' AND pid<>pg_backend_pid();" 2>/dev/null | tr '|' ',')
  # PgBouncer SHOW POOLS for db "app" (psql from the pg container; empty if PgBouncer isn't running)
  pools=$(docker exec -e PGPASSWORD=lab pg psql -h pgbouncer -p 6432 -U postgres pgbouncer -At -F' ' -c "SHOW POOLS;" 2>/dev/null \
          | awk '$1=="app"{printf "%s,%s,%s,%d", $3,$4,$7,$14*1000+$15/1000}')
  echo "$(date +%T),${c:-,},${pg:-,},${pgb},${avail},${pools:-,,,},${waits:-,,}" >> "$OUT"
  sleep 5
done
