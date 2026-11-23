# Step 1: Baseline (measure before touching anything)

[← Step 0](step0_data.md) · [Summary](00_SUMMARY.md) · Next: [Step 2 →](step2_indexes.md)

## Test
- **32 concurrent clients** for **120 seconds** (after a 30 s warm-up that's discarded).
- **90% feed reads** (`bench/feed.sql`) and **10% new posts** (`bench/write.sql`).

## Result

| Metric | Value |
|---|---:|
| Throughput | **0.81 transactions/sec** |
| Transactions completed | 120 in 2 minutes |
| Feed p50 | 47,052 ms |
| **Feed p95** | **55,788 ms (about 56 seconds)** |
| Feed p99 | 57,628 ms |
| Write p95 | 114 ms |
| Errors | 0 |

## Why it's slow

**A single feed query alone takes 2.1 seconds.** The plan shows:
- `Parallel Seq Scan on posts`: it reads **all 10 million posts**.
- 154,006 pages (about 1.2 GB) read, mostly from disk.
- All that to return about **190 rows** (the posts of the 20 people the user follows).

**Under load it gets much worse:** 32 queries each scan the whole table at once, competing for 4 CPUs and the disk, so a 2-second query waits about 45 seconds.

**`pg_stat_statements` confirms it:** the feed query takes **100%** of database time. Writes are fine (11 ms average).

## Conclusion
The cause is confirmed: **no index for the feed query**. That's exactly what Step 2 fixes.

## Raw files
- Plan: `raw/step1/explain_feed.txt`
- Benchmark: `raw/step1/baseline/pgbench.out`, `percentiles.txt`, `pg_stat_statements.txt`
