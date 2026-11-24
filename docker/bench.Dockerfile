# Benchmark client: pgbench + psql (from postgres:16) plus python3/psycopg for the bench/*.py scripts
FROM postgres:16
RUN apt-get update && apt-get install -y --no-install-recommends python3 python3-psycopg \
    && rm -rf /var/lib/apt/lists/*
