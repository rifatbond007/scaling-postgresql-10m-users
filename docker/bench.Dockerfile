# pgbench/psql + python3/psycopg for loadgen and percentile scripts
FROM postgres:16
RUN apt-get update && apt-get install -y --no-install-recommends python3 python3-psycopg python3-redis \
    && rm -rf /var/lib/apt/lists/*
