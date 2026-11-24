#!/usr/bin/env python3
"""Step 4: read-your-writes test (proposal section 06).

Each iteration, a random user writes a post on the primary and immediately reads
their own latest posts. A "miss" means the new post wasn't in what they read.

Modes:
  replica  - no routing: read from a random replica (the classic bug)
  lsn      - the proposal's LSN routing: after a write, remember the primary's WAL position
             for that user; read from a replica only if it has replayed past it, else the primary

The proposal keeps the LSN in Redis so every app server sees it. This test is a single
process, so a dict stands in for Redis; the routing logic is the same.

Usage: ryw_test.py MODE ITERATIONS [PAUSE_MS]
  PAUSE_MS: wait between the write and the read (a user refreshing later), default 0
"""
import random, sys, time
import psycopg  # password: libpq reads PGPASSWORD (set from .env by docker compose)

MODE, N = sys.argv[1], int(sys.argv[2])
PAUSE = (int(sys.argv[3]) if len(sys.argv) > 3 else 0) / 1000
connect = lambda host: psycopg.connect(host=host, dbname="app", user="postgres", autocommit=True)
primary = connect("pg")
replicas = [connect("replica1"), connect("replica2")]
lsn_store = {}   # stands in for Redis: user_id -> LSN of their last write


def after_write(conn_primary, user_id):
    # proposal: lsn = SELECT pg_current_wal_lsn(); redis.set(f"lsn:{user_id}", lsn, ex=60)
    lsn_store[user_id] = conn_primary.execute("SELECT pg_current_wal_lsn()").fetchone()[0]


def pick_connection(user_id):
    need = lsn_store.get(user_id)
    if not need:
        return random.choice(replicas), "replica"        # no recent write
    for r in random.sample(replicas, len(replicas)):
        ok = r.execute("SELECT pg_last_wal_replay_lsn() >= %s::pg_lsn", (need,)).fetchone()[0]
        if ok:
            return r, "replica"                          # this replica has caught up
    return primary, "primary"                            # none has caught up yet


MY_POSTS = """SELECT id FROM posts WHERE user_id = %s AND NOT is_deleted
              ORDER BY created_at DESC LIMIT 30"""

misses, served = 0, {"replica": 0, "primary": 0}
read_ms = []
for i in range(N):
    uid = random.randint(1, 1_000_000)
    new_id = primary.execute(
        "INSERT INTO posts (user_id, body) VALUES (%s, %s) RETURNING id", (uid, f"ryw test {i}")
    ).fetchone()[0]

    if MODE == "lsn":
        after_write(primary, uid)
    time.sleep(PAUSE)

    t0 = time.perf_counter()
    if MODE == "lsn":
        conn, where = pick_connection(uid)
    else:
        conn, where = random.choice(replicas), "replica"
    ids = [r[0] for r in conn.execute(MY_POSTS, (uid,)).fetchall()]
    read_ms.append((time.perf_counter() - t0) * 1000)

    served[where] += 1
    if new_id not in ids:
        misses += 1

read_ms.sort()
print(f"mode={MODE} pause_ms={int(PAUSE*1000)} iterations={N} misses={misses} ({100*misses/N:.1f}%) "
      f"served_by_replica={served['replica']} served_by_primary={served['primary']} "
      f"read_ms_p50={read_ms[N//2]:.2f} read_ms_p95={read_ms[int(N*.95)]:.2f}")
