#!/usr/bin/env bash
# Step 4 (host): run_split.sh with sample_replicas.sh alongside the measured part.
# Usage: bench/run_split_sampled.sh LABEL READ_CLIENTS "READ_HOSTS" WRITES_PER_SEC SECONDS
set -u
cd "$(dirname "$0")/.."
LABEL=$1; T=$5
( sleep 45; bench/sample_replicas.sh "raw/$LABEL.samples.csv" "$T" ) &   # after prewarm + 30 s warm-up
SP=$!
docker compose --env-file .env -f docker/single.yml run --rm bench "/bench/run_split.sh $1 $2 \"$3\" $4 $5" 2>&1 | grep -v "Container\|Creat"
wait $SP 2>/dev/null; mv "raw/$LABEL.samples.csv" "raw/$LABEL/samples.csv" 2>/dev/null
