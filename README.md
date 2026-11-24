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
scripts/    set-passwords.sh
Makefile    all common commands (make help)
.env        local passwords (git-ignored); .env.example is the template
```

## Setup
```bash
make env        # creates .env with random passwords (git-ignored; template: .env.example)
make up         # start Postgres
make seed       # schema + 1M users / 20M follows / 10M posts (~5 min)
make indexes    # final Step 2 indexes
make help       # list every command
```

## Common commands
```bash
make psql                                   # SQL shell on the primary
make bench LABEL=step5/x CLIENTS=32         # pgbench, 90/10 feed/write -> raw/step5/x/
make bench-sampled LABEL=step3/x CLIENTS=2000 PORT=6432 HOST=pgbouncer   # + CPU/memory/pool sampling
make top-queries / make index-report        # Step 1 / Step 2 inspection queries

make pool-up / make pool-down               # Step 3: PgBouncer on port 6432
make up PG_MAX_CONN=2500                    # Step 3: primary with a different connection limit

make replicas-up / make replicas-down       # Step 4: 2 read replicas on ports 5433, 5434
make bench-split LABEL=step4/x CLIENTS=28 READ_HOSTS=replica1,replica2 WRITE_RATE=30
make ryw RYW_MODE=lsn RYW_N=1000            # Step 4: read-your-writes test

make ps / make stop / make down             # status / stop / remove containers (data kept)
make rebuild CONFIRM=yes                    # DELETE all data and rebuild from scratch
```

## Passwords
- Real passwords live only in **`.env`** (git-ignored, mode 600). `.env.example` is the committed template.
- Docker Compose refuses to start if `.env` is missing a password.
- Python scripts don't take a password: libpq reads `PGPASSWORD`, which Compose sets from `.env`.
- Changed `.env`? Run `make set-passwords` to apply it to the running databases, replicas and PgBouncer.
- Inside the `pg` container, local connections are trusted (Postgres image default), so `docker exec pg psql` needs no password.

GUI connection: host `localhost`, port `5432`, db `app`, user `postgres`, password = `POSTGRES_PASSWORD` from `.env`.
Disconnect GUI tools while a benchmark runs.

## Scaled-down settings (vs. the proposal)
Postgres container: 2 GB RAM / 4 CPU, `shared_buffers=512MB`. Bench client: 4 CPU.
These are kept fixed across all steps so results compare fairly.
