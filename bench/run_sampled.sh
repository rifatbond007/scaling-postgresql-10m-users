#!/usr/bin/env bash
# Usage (host): bench/run_sampled.sh LABEL CLIENTS THREADS SECONDS "scripts" [PORT] [HOST]
set -u
cd "$(dirname "$0")/.."
LABEL=$1; T=$4
mkdir -p "raw/$LABEL"
( sleep 40; bench/sample.sh "raw/$LABEL.samples.csv" "$T" ) &   # start after prewarm + 30 s warm-up
SP=$!
docker compose -f docker/single.yml run --rm bench "/bench/run.sh $1 $2 $3 $4 \"$5\" ${6:-5432} ${7:-pg}" 2>&1 | grep -v "Container\|Creat"
wait $SP 2>/dev/null; mv "raw/$LABEL.samples.csv" "raw/$LABEL/samples.csv" 2>/dev/null
