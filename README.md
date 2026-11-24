# Scaling PostgreSQL lab

Implements Part B of `Scaling_PostgreSQL_10M_Users.docx`: one change at a time, measured before and after.

👉 **Results: open [`report/00_SUMMARY.md`](report/00_SUMMARY.md)** and press `Ctrl+Shift+V` in VS Code to preview it.

## Project layout
```
report/     human-readable results, one page per step   ← read these
raw/        machine output per step (pgbench, EXPLAIN plans, txlog/)
sql/        schema.sql, seed.sql, step1_top_queries.sql, step2_indexes.sql, step2_index_report.sql
bench/      workloads (feed*.sql, write.sql), run.sh, run_sampled.sh, sample.sh, percentiles.py,
            count_connect.py, txmode_pitfall.py, run_split*.sh, sample_replicas.sh, ryw_test.py
docker/     single.yml (Postgres, PgBouncer, replicas, bench client), bench.Dockerfile, pgbouncer/, replica/
```

## Commands
```bash
# start the database
docker compose -f docker/single.yml up -d pg

# open a SQL shell
docker exec -it pg psql -U postgres -d app

# run a benchmark: LABEL CLIENTS THREADS SECONDS "scripts"  -> output in raw/LABEL/
docker compose -f docker/single.yml run --rm bench '/bench/run.sh step3/example 32 8 120 "feed_lateral.sql@9 write.sql@1"'

# Step 3: PgBouncer (port 6432). First time after a (re)seed: regenerate its auth file
docker/pgbouncer/make-userlist.sh
docker compose -f docker/single.yml --profile pool up -d pgbouncer
# benchmark through PgBouncer, with CPU/memory/connection sampling -> raw/LABEL/samples.csv
bench/run_sampled.sh step3/example 2000 16 120 "feed_lateral.sql@9 write.sql@1" 6432 pgbouncer
# change pool size: edit docker/pgbouncer/pgbouncer.ini, then `docker restart pgbouncer` (RELOAD won't see the edit)

# Step 4: 2 read replicas (ports 5433, 5434). Prepare the primary once, then start them
docker/replica/setup-primary.sh
docker compose -f docker/single.yml --profile replicas up -d replica1 replica2
# reads on given hosts + writes at a fixed rate on the primary, with lag/CPU sampling
bench/run_split_sampled.sh step4/example 28 "replica1,replica2" 30 120
# read-your-writes test: MODE (replica | lsn) ITERATIONS [PAUSE_MS]
docker compose -f docker/single.yml run --rm bench 'python3 /bench/ryw_test.py lsn 1000'

# Postgres with a different connection limit
PG_MAX_CONN=2500 docker compose -f docker/single.yml up -d pg

# rebuild from scratch (deletes all data)
docker compose -f docker/single.yml --profile replicas down -v
docker compose -f docker/single.yml up -d pg
docker exec -i pg psql -U postgres -d app < sql/schema.sql
docker exec -i pg psql -U postgres -d app < sql/seed.sql
docker exec -i pg psql -U postgres -d app < sql/step2_indexes.sql   # final Step 2 indexes
docker/pgbouncer/make-userlist.sh                                   # new hash for PgBouncer
```

GUI connection: host `localhost`, port `5432`, db `app`, user `postgres`, password `lab`.
Disconnect GUI tools while a benchmark runs.

## Scaled-down settings (vs. the proposal)
Postgres container: 2 GB RAM / 4 CPU, `shared_buffers=512MB`. Bench client: 4 CPU.
These are kept fixed across all steps so results compare fairly.
