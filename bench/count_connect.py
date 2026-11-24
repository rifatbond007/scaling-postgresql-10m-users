#!/usr/bin/env python3
"""Open N connections and keep them open; count how many succeed and why the rest fail.
Usage: count_connect.py N HOST PORT"""
import sys, collections, psycopg
n, host, port = int(sys.argv[1]), sys.argv[2], int(sys.argv[3])
held, errors = [], collections.Counter()
for _ in range(n):
    try:
        held.append(psycopg.connect(host=host, port=port, dbname="app", user="postgres", password="lab", connect_timeout=5))
    except psycopg.OperationalError as e:
        msg = str(e).strip().splitlines()[-1]
        errors[msg.split("FATAL:")[-1].strip()[:70]] += 1
print(f"attempted={n} connected={len(held)} refused={n-len(held)}")
for msg, c in errors.most_common():
    print(f"  {c:5d} x {msg}")
for c in held: c.close()
