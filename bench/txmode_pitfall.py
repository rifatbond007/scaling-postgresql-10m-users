#!/usr/bin/env python3
"""Show why session-level SET is unsafe behind PgBouncer transaction pooling.
1) Client A runs SET work_mem='77MB' (session level). 20 other clients keep running SHOW work_mem.
   Count how many of their answers are 77MB (leaked) and how often A itself still sees 77MB (lost).
2) Same with SET LOCAL inside a transaction (the fix): nothing should leak.
Usage: txmode_pitfall.py HOST PORT"""
import sys, threading, collections, psycopg
host, port = sys.argv[1], int(sys.argv[2])
conn = lambda: psycopg.connect(host=host, port=port, dbname="app", user="postgres", password="lab", autocommit=True)
ROUNDS = 200

def others(results):
    c = conn()
    for _ in range(ROUNDS):
        results[c.execute("SHOW work_mem").fetchone()[0]] += 1
    c.close()

def fresh_server_connections():
    """Close all server backends directly on Postgres, so pooled connections start with default settings.
    (RESET sent through PgBouncer only reaches whichever server connection it happens to get.)"""
    d = psycopg.connect(host="pg", port=5432, dbname="app", user="postgres", password="lab", autocommit=True)
    d.execute("SELECT pg_terminate_backend(pid) FROM pg_stat_activity "
              "WHERE backend_type='client backend' AND pid <> pg_backend_pid()")
    d.close()

def run(mode):
    fresh_server_connections()
    a = conn()
    if mode == "session":
        a.execute("SET work_mem = '77MB'")
    seen_by_a, leaked = collections.Counter(), collections.Counter()
    threads = [threading.Thread(target=others, args=(leaked,)) for _ in range(20)]
    for t in threads: t.start()
    for _ in range(ROUNDS):
        if mode == "session":
            seen_by_a[a.execute("SHOW work_mem").fetchone()[0]] += 1
        else:
            with a.transaction():
                a.execute("SET LOCAL work_mem = '77MB'")
                seen_by_a[a.execute("SHOW work_mem").fetchone()[0]] += 1
    for t in threads: t.join()
    a.close()
    tot_a, tot_o = sum(seen_by_a.values()), sum(leaked.values())
    print(f"--- {mode} SET ---")
    print(f"  client A saw its own 77MB:          {seen_by_a['77MB']}/{tot_a} ({100*seen_by_a['77MB']/tot_a:.0f}%)")
    print(f"  other clients saw A's 77MB (leak):  {leaked['77MB']}/{tot_o} ({100*leaked['77MB']/tot_o:.1f}%)")

run("session")
run("local")
