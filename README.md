# Scaling PostgreSQL lab

Implements Part B of `Scaling_PostgreSQL_10M_Users.docx`: one change at a time, measured before and after.

👉 **Results: open [`report/00_SUMMARY.md`](report/00_SUMMARY.md)** and press `Ctrl+Shift+V` in VS Code to preview it.

## Project layout
```
report/     human-readable results, one page per step   ← read these
raw/        machine output per step (pgbench, EXPLAIN plans, txlog/)
sql/        schema.sql, seed.sql
bench/      workload scripts (feed*.sql, write.sql), run.sh, percentiles.py
docker/     single.yml (Postgres + bench client), bench.Dockerfile
app/        Python routing/sharding code (Steps 4-7)
```

## Commands
```bash
# start the database
docker compose -f docker/single.yml up -d pg

# open a SQL shell
docker exec -it pg psql -U postgres -d app

# run a benchmark: LABEL CLIENTS THREADS SECONDS "scripts"  -> output in raw/LABEL/
docker compose -f docker/single.yml run --rm bench '/bench/run.sh step3/example 32 8 120 "feed_lateral.sql@9 write.sql@1"'

# rebuild from scratch (deletes all data)
docker compose -f docker/single.yml down -v
docker compose -f docker/single.yml up -d pg
docker exec -i pg psql -U postgres -d app < sql/schema.sql
docker exec -i pg psql -U postgres -d app < sql/seed.sql
```

GUI connection: host `localhost`, port `5432`, db `app`, user `postgres`, password `lab`.
Disconnect GUI tools while a benchmark runs.

## Scaled-down settings (vs. the proposal)
Postgres container: 2 GB RAM / 4 CPU, `shared_buffers=512MB`. Bench client: 4 CPU.
These are kept fixed across all steps so results compare fairly.
