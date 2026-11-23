#!/usr/bin/env python3
"""Per-script latency percentiles from pgbench -l logs.

pgbench log columns: client_id tx_no latency_us script_no epoch_s epoch_us
The proposal's awk mixed feed and write latencies; this splits them by script_no.
Usage: percentiles.py PREFIX [script names in -f order...]
"""
import glob, sys

prefix = sys.argv[1]
names = sys.argv[2:] or None
lat = {}
for path in glob.glob(prefix + ".*"):
    with open(path) as fh:
        for line in fh:
            parts = line.split()
            if len(parts) < 4 or parts[2] == "failed":
                continue
            lat.setdefault(int(parts[3]), []).append(int(parts[2]))

def pct(a, p):
    return a[min(len(a) - 1, int(len(a) * p))] / 1000

allv = sorted(v for vs in lat.values() for v in vs)
rows = [("all", allv)] + [
    ((names[k] if names and k < len(names) else f"script{k}"), sorted(v))
    for k, v in sorted(lat.items())
]
print(f"{'script':<10}{'n':>9}{'p50 ms':>10}{'p95 ms':>10}{'p99 ms':>10}")
for name, a in rows:
    if a:
        print(f"{name:<10}{len(a):>9}{pct(a,.5):>10.2f}{pct(a,.95):>10.2f}{pct(a,.99):>10.2f}")
