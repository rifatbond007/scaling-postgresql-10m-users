# Scaling PostgreSQL: results summary

> **How to read this in VS Code:** open this file and press **`Ctrl+Shift+V`** (or right-click the tab → *Open Preview*) to see the tables rendered.

## Where things are

| Folder | What's inside | Read it? |
|---|---|---|
| `report/` | **One page per step**, written for people | ✅ Start here |
| `raw/stepN/` | Machine output: pgbench output, EXPLAIN plans, per-transaction logs (`txlog/`) | Only to check a number |
| `sql/`, `bench/`, `docker/` | Scripts that produce everything | To rerun |

## Progress

| Step | Topic | Status | Page |
|---|---|---|---|
| 0 | Lab and data (1M users) | ✅ Done | [step0_data.md](step0_data.md) |
| 1 | Baseline measurement | ✅ Done | [step1_baseline.md](step1_baseline.md) |
| 2 | Indexes and query rewrite | ✅ Done | [step2_indexes.md](step2_indexes.md) |
| 3 | PgBouncer connection pooling | ✅ Done | [step3_pgbouncer.md](step3_pgbouncer.md) |
| 4 | Read replicas | ⏳ Next | |
| 5 | Partitioning | ⬜ | |
| 6 | Sharding | ⬜ | |
| 7 | Live bucket move | ⬜ | |
| 8 | Final comparison and hot shard | ⬜ | |

## Running scoreboard

Workload: 32 clients, 90% feed reads / 10% writes, 120 s.

| After step | Throughput (TPS) | Feed p95 | One feed query | Gain vs. previous row |
|---|---:|---:|---:|---|
| 1. Baseline | 0.81 | 55,788 ms | 2,131 ms | |
| 2. + index on posts | 770 | 100 ms | 2.9 ms | **~950× TPS** |
| 2. + query rewrite, partial and covering index | 1,353 | 67 ms | 3.4 ms | Small; mostly cache warm-up (see Step 2) |

**Step 3: thousands of clients** (lab rebuilt; compare within Step 3 only)

| Setup | Real server connections | Postgres memory | Errors |
|---|---:|---:|---|
| 2,000 direct, `max_connections=100` | 100 | | ❌ 1,900 refused ("too many clients") |
| 2,000 direct, `max_connections=2500` | ~1,200, then killed | over 2 GB | 💥 Out of memory |
| 300 direct | 300 | 1.45 GB | 0 |
| **2,000 through PgBouncer** | **8–20** | **~0.6 GB** | **0** ✅ |

## Key findings so far
1. **The feed was slow because of a missing index.** Every feed read scanned all 10M posts.
2. **One index fixed almost everything:** throughput rose about 950× and feed p95 dropped from 56 s to 0.1 s.
3. **The query rewrite and partial index add little on this data.** Users have only about 9 posts each. Retest with celebrity users in Step 8.
4. **Postgres can't take thousands of direct connections.** Each costs 1.5–2.6 MB, and the 2 GB server died at about 1,200. **PgBouncer** serves 2,000 clients on 8–20 real connections with 0 errors.
5. **PgBouncer's proven win is memory and stability, not speed.** Throughput against direct connections was inconclusive.
6. **Pool size depends on the bottleneck:** small (about 2 × cores) when CPU-bound, larger when waiting on disk.
7. **Never use session `SET` behind transaction pooling:** it leaked to other clients in every run (0.5–29% of their answers). Use `SET LOCAL`.
8. **Measurement on a laptop is noisy.** The cache doesn't fit in the 2 GB container, so throughput varied up to 3× with the same settings. Only alternating, back-to-back runs are compared.

## Test machine
8 CPU cores, 7 GB RAM laptop. The Postgres container is limited to 2 GB RAM and 4 CPUs, with `shared_buffers=512MB`; the benchmark client gets 4 CPUs. This is scaled down from the proposal (16–64 GB), so compare the steps with each other, not the absolute numbers with production.
