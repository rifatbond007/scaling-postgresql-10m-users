# Step 3: Connection pooling with PgBouncer

[← Step 2](step2_indexes.md) · [Summary](00_SUMMARY.md) · Next: [Step 4 →](step4_replicas.md)

**Question:** what happens when thousands of clients connect, and does PgBouncer fix it?

Workload as before: 90% feed (`feed_lateral.sql`) / 10% writes, 120 s, Step 2 indexes in place. PgBouncer 1.26 in **transaction mode**.

> ⚠️ **The lab was rebuilt before this step** (all Docker data deleted, reseeded with the same script). Compare runs within this page, and preferably only runs done back to back. See "Measurement caveat" at the end.

## Verdict

> Server connection counts exclude the monitoring script's own connection. The first version of this page counted it, so it showed one extra (e.g. 9 instead of 8).

| Claim | Status | Evidence |
|---|---|---|
| Postgres refuses connections over `max_connections` | ✅ Proven | 1,900 of 2,000 refused (counted) |
| Raising `max_connections` to 2,500 isn't a fix | ✅ Proven | Out of memory at ~1,200 connections |
| PgBouncer serves 2,000 clients with 0 errors on a few server connections | ✅ Proven | 8–20 server connections, 0 failed transactions |
| PgBouncer uses far less server memory than direct connections | ✅ Proven | 0.61 GB vs. 1.45 GB at 300 clients |
| PgBouncer gives *higher throughput* than direct | ❓ **Not proven** | Won 1 round and lost 1 round at 300 clients |
| Best pool size is about 2 × CPU cores | ⚠️ **Only when CPU-bound** | When disk-bound, pool 20 beat pool 8 in both rounds |
| Session `SET` breaks in transaction mode | ✅ Proven | Lost 67–98% of the time, leaked to 0.5–29% of other clients' answers (6 runs) |

---

## A: 2,000 clients direct, `max_connections=100` ❌

Counted with `bench/count_connect.py` (opens 2,000 connections and holds them):

```
attempted=2000 connected=100 refused=1900
   1900 x sorry, too many clients already
```

100 rather than 97 because the test user `postgres` is an admin and may also use the 3 reserved slots; a normal app user would get 97. pgbench itself aborts the whole run at the first refused client.

## B: 2,000 clients direct, `max_connections=2500` 💥

Each connection is a separate Postgres process. Postgres memory, sampled every second while clients connected:

| Second | Server connections | Postgres memory |
|---:|---:|---:|
| 1 | 43 | 598 MiB |
| 2 | 649 | 1,488 MiB |
| 3 | 1,206 | **killed (out of memory)** |

How much memory direct connections need **under load** (with a full cache):

| Direct clients | Peak Postgres memory |
|---:|---:|
| 200 | 1,296 MiB |
| 300 | 1,498 MiB |
| 400 | 1,818 MiB |
| 600 | **killed (out of memory)** |

**Memory per connection: about 1.5 MB idle, about 2.6 MB under load.** In this 2 GB container about 400 direct clients is the ceiling.

## C: 2,000 clients through PgBouncer ✅

| | Value |
|---|---|
| Errors | **0** |
| Real Postgres connections | **8** (pool 8) to **20** (pool 20) |
| Postgres memory | ~620 MB, the same as idle |
| PgBouncer cost | **25 MB RAM, ~12% of one CPU** |
| Clients waiting in PgBouncer (`SHOW POOLS`, sampled during the run) | **~1,800 of 2,000** on average |

**Why latency is seconds:** most clients are waiting in PgBouncer's line. 2,000 clients sending non-stop through a few connections must take turns. Little's law: latency ≈ clients ÷ TPS, which matches every run. Real users pause between requests, so they would wait far less.

## D: Direct vs. PgBouncer, 300 clients each (fits in memory)

Run in alternating order so cache warm-up can't favor one side. PgBouncer pool = 8.

| Run (in order) | TPS | Feed p95 | Server connections | Postgres CPU | Postgres memory | Clients waiting (avg) / longest wait |
|---|---:|---:|---:|---:|---:|---|
| Direct #1 | 428 | 938 ms | 300 | 204% | 1.45 GiB | |
| PgBouncer #1 | **856** | **419 ms** | 8 | 140% | 610 MiB | 292 / 460 ms |
| Direct #2 | 473 | 819 ms | ~300 | 201% | 1.48 GiB | |
| PgBouncer #2 | 384 | 931 ms | 8 | **86%** | 624 MiB | 292 / 899 ms |

- ✅ **Memory: PgBouncer uses 2.4× less**, and about 37× fewer server connections (8 vs. 300).
- ❓ **Throughput: no winner.** PgBouncer won round 1 by 2× and lost round 2. In round 2 Postgres sat at 86% CPU (of 400%) while 292 clients waited: with only 8 connections, few disk reads happen at once. Section E confirms it.

## E: Pool size depends on the bottleneck

At 2,000 clients, alternating. The last columns show what active server connections were doing (sampled from `pg_stat_activity`).

| Pool (in order) | TPS | Feed p95 | Waiting on disk | Running on CPU | Postgres CPU |
|---|---:|---:|---:|---:|---:|
| 8 | 399 | 5,379 ms | 7.1 | 0.3 | 85% |
| 20 | **419** | **4,927 ms** | 18.3 | 0.3 | 98% |
| 8 | 382 | 5,683 ms | 7.3 | 0.1 | 77% |
| 20 | **416** | **4,975 ms** | 18.2 | 0.4 | 97% |

**Disk-bound (data not cached): pool 20 beat pool 8 in both rounds (+5–9%).** Nearly every server connection was waiting on disk, so more connections = more disk reads in flight.

Earlier in the session, **with a warm cache (CPU-bound)**, single runs went the other way:

| Pool | TPS | Feed p95 | Postgres CPU |
|---:|---:|---:|---:|
| 8 | 1,457 | 1,498 ms | 267% |
| 20 | 1,124 / 1,368 | 2,296 / 1,788 ms | 314% |
| 40 | 1,302 | 1,880 ms | 328% |

**Rule:** CPU-bound → a small pool (about 2 × cores) avoids contention. Disk-bound → a bigger pool keeps the disk busy. Find out which you are by checking `wait_event_type` in `pg_stat_activity` before tuning.

## F: What transaction mode breaks

`bench/txmode_pitfall.py`: client A runs `SET work_mem='77MB'`, and 20 other clients keep checking `SHOW work_mem`. Every phase starts with fresh server connections.

| Path | Setting | A sees its own 77 MB | Other clients see A's 77 MB (leak) |
|---|---|---:|---:|
| PgBouncer | `SET` (session) | **2–33%** (lost 67–98% of the time) | **0.5–29%** of answers ❌ |
| PgBouncer | `SET LOCAL` inside a transaction | 100% | 0% ✅ |
| Direct | `SET` | 100% | 0% |
| Direct | `SET LOCAL` | 100% | 0% |

PgBouncer rows: range over 6 runs (17/17.4%, 2/0.5%, 21/19.0%, 31/28.8%, 33/26.1%, 21/21.1%). The size depends on which server connections PgBouncer hands out, but **the leak happened in every run**.

In transaction mode each transaction may get a different server connection. A session `SET` stays on whichever connection ran it and **leaks to strangers**. Use `SET LOCAL`, or route such work through a direct connection. The same applies to session advisory locks, `LISTEN/NOTIFY` and temp tables (not tested).

A real bug while building this test: my cleanup sent `RESET` through PgBouncer, which didn't reach all server connections, so the leaked setting survived into the next phase. That's the same pitfall in practice.

---

## Conclusions
1. **Thousands of direct connections don't work:** refused at the limit, and out of memory when the limit is raised (about 2.6 MB per active connection).
2. **PgBouncer handles 2,000 clients with 0 errors** on 8–20 server connections, for 25 MB of overhead.
3. **PgBouncer's proven win is memory and stability, not speed.** Throughput against direct was inconclusive.
4. **Pool size: small for CPU-bound, larger for disk-bound.** Measure wait events first.
5. **Never use session-level `SET` behind transaction pooling.** It leaks between clients.

## Measurement caveat
With the same settings, absolute TPS varied 3× during this step (about 400 to 1,450). The 2 GB container can't cache the 2.5 GB of table and indexes, so results depend on what the previous run left in cache. The direct 300-connection runs used 1.45 GB for connections and pushed the cache out. **Compare only alternating, back-to-back runs (sections D and E).** Section C's single runs are indicative only.

## Problems hit along the way
- The first reference run was invalid (Firefox using about 2 GB of RAM). Discarded.
- The first pool-size sweep was invalid: `sed -i` replaces the config file, and a container with one file mounted keeps reading the old copy. Fixed by restarting PgBouncer for each change and checking `SHOW CONFIG`.
- The first direct-vs-PgBouncer series (600 clients) crashed: my idle-connection estimate (1.5 MB) underestimated memory under load (2.6 MB), and the loop didn't stop when Postgres died. Remeasured, rerun at 300, and the loop now stops on failure.
- Postgres can't use swap (`memswap_limit: 2g`), so an out-of-memory crash only kills the database, not the laptop.

## Raw files (`raw/step3/`)
| Folder or file | What |
|---|---|
| `A_direct_2000_max100/connect_count.txt` | Refused-connection count |
| `B_direct_2000_max2500/connect_ramp.csv` | Memory per second until out of memory |
| `D_direct_capacity_probe/probe.txt` | Memory at 200/300/400 direct clients |
| `C_pgbouncer_2000_pool{8,20,40}/`, `..._pool20_repeat/` | Single runs, warm cache |
| `D_300_{direct,pgb}_r{1,2}/` | Alternating direct vs. PgBouncer |
| `E_pool{8,20}_r{1,2}/` | Alternating pool sizes, with wait events |
| `txmode_pitfall.txt` | `SET` leak test |
| `ref_direct_32*` | 32-client reference runs |

Each run folder has `samples.csv`: every 5 s, server connections, Postgres and PgBouncer CPU/memory, `SHOW POOLS` (clients served, waiting, longest wait), and the wait events of active connections (disk / lock / CPU).
