# Step 4: Read replicas

[← Step 3](step3_pgbouncer.md) · [Summary](00_SUMMARY.md)

**Question:** can feed reads move to replicas to take load off the primary, and can users still always see their own new post?

## Setup
- **Primary** (`pg`, 2 GB / 4 CPU, as in Steps 0–3) plus **2 streaming replicas** (`replica1`, `replica2`: 1 GB / 2 CPU each, `shared_buffers=256MB`). The replicas are smaller because the laptop can't fit 3 × 2 GB.
- **Primary preparation** (`docker/replica/setup-primary.sh`):
  - a `replicator` role and a `pg_hba.conf` rule allowing replication;
  - one replication slot per replica;
  - `max_slot_wal_keep_size = 4GB`, so a dead replica can't fill the primary's disk (the proposal's warning).

  The proposal's `wal_level`, `max_wal_senders`, `max_replication_slots` and `hot_standby` settings are already Postgres 16 defaults.
- **Cloning:** each replica copies the primary with `pg_basebackup -R -S <slot>` (`docker/replica/start-replica.sh`). Copying 6 GB took **about 22 s per replica**.
- **Workload** (`bench/run_split.sh`): two pgbench runs at once.
  - Feed reads: 28 clients, as fast as possible, against the chosen hosts. libpq `load_balance_hosts=random` spreads them over the replicas.
  - Writes: 4 clients at a fixed 30/s on the primary, about 10% of reads, as in the proposal's 90/10 mix.
- **Verified:** both replicas `streaming`, same row counts as the primary, and writes rejected (`cannot execute INSERT in a read-only transaction`).

## Verdict

| Proposal check | Result |
|---|---|
| Read-your-writes: 0 misses with routing | ✅ **0 / 1,000** with LSN routing, even with a forced 2 s lag (100% missed without routing) |
| Replica lag measured | ✅ Median **~300 ms**, p95 **410–540 ms** under load. Idle: under 10 ms. |
| Primary relieved of reads | ✅ Primary CPU **85–98% → ~1%** |
| More read throughput with replicas | ❌ **Not on this laptop**: all nodes share one SSD (details below) |
| Replica query conflicts | ✅ None (0 snapshot, lock, buffer-pin or deadlock cancellations) |

---

## A: 1 node vs. primary + 2 replicas

Alternating, 120 s each.

| Run (in order) | Feed reads TPS | Feed p95 | Primary CPU | Replica CPU | Replay lag p50 / p95 |
|---|---:|---:|---:|---|---|
| 1 node #1 | 503 | 85 ms | 85% | | 335 / 469 ms |
| Replicas #1 | 145 | 223 ms | **1%** | 28% / 22% | 301 / 531 ms |
| 1 node #2 | 641 | 59 ms | 98% | | 349 / 541 ms |
| Replicas #2 | 149 | 226 ms | **1%** | 25% / 27% | 299 / 410 ms |

- ✅ **The primary is relieved:** CPU went from 85–98% to about 1%. It now only handles writes.
- ❌ **Reads got 3.5–4× slower.** This comparison isn't fair: each replica has half the primary's memory and CPUs. Section B fixes that.

## B: 1 replica vs. 2 replicas (same size: a fair scale-out test)

| Run (in order) | Read TPS | Feed p95 | Replica CPU |
|---|---:|---:|---|
| 1 replica #1 | **145** | 225 ms | 45% |
| 2 replicas #1 | 130 | 262 ms | 24% + 29% |
| 1 replica #2 | **152** | 222 ms | 57% |
| 2 replicas #2 | 136 | 283 ms | 43% + 22% |

**Adding a second replica made reads about 10% *slower*, consistently in both rounds.**

### Why: one shared SSD
Measured during a run with reads on the replicas:

| | Value |
|---|---|
| SSD reads | **~18,000 per second**, almost all from the replicas |
| Replica cache hit ratio | **~30%** (1 GB can't hold the 2.5 GB of hot table and index data) |
| Replica CPU | 22–57%: mostly waiting on disk |

- In production each replica has its own disk and RAM, so adding one adds disk capacity. **Here every node reads from the same SSD**, so a second replica adds CPU (not needed) and no disk capacity.
- Worse, the two 1 GB caches each hold copies of the same randomly accessed data, so together they cache less of what's needed than one replica does.

### Side effect: replica reads slowed the primary's writes

| | Real time per write (p50) |
|---|---:|
| Primary idle | 2.9 ms |
| 4 readers | 40–58 ms |
| 28 readers (on primary or on replicas) | **320–400 ms** |

The writer connections were waiting on WAL flushes: `LWLock:WALWrite` in 60 of 80 samples and `IO:WALSync` in 20. Under 18,000 reads/s, each flush to the shared SSD takes hundreds of milliseconds. So **writes achieved only about 11–12/s instead of the 30/s target** in every run. pgbench's write latency (seconds) is mostly time spent behind its schedule; the real per-write time above excludes that.

## C: Read-your-writes (`bench/ryw_test.py`)

Each try: a random user writes a post on the primary, then reads their own latest 30 posts. **Miss** = the new post isn't there.
- **No routing:** always read from a random replica.
- **LSN routing:** the proposal's code. After the write, store `pg_current_wal_lsn()` for the user; read from a replica only if `pg_last_wal_replay_lsn() >= that LSN`, else from the primary. A Python dict stands in for Redis, since it's one process.

| Condition | Pause before read | No routing: misses | LSN routing: misses | LSN: reads sent to primary |
|---|---:|---:|---:|---:|
| Idle | 0 ms | **997 / 1,000** | **0 / 1,000** ✅ | 997 |
| Forced 2 s lag (`recovery_min_apply_delay`) | 0 ms | **1,000 / 1,000** | **0 / 1,000** ✅ | 1,000 |
| Idle | 10 ms | 0 / 300 | 0 / 300 | 0 |
| Idle | 100 ms | 0 / 300 | 0 / 300 | 0 |
| **Under load** (lag 250–660 ms) | 100 ms | **150 / 150** | **0 / 150** ✅ | 145 |

- **LSN routing never lost a post:** 0 misses in every case. ✅ The proposal's target is met.
- **Without routing the bug is real:** a read right after a write misses almost every time, even on an idle system, and under load even a 100 ms pause misses 100%.
- **The cost:** when reads follow writes closely, LSN routing sends nearly all of them to the primary, and the extra LSN check adds about 0.5 ms per read when idle and 6.5 ms under load (p50). Once the replica has caught up (idle, ≥10 ms later), it uses the replicas again.
- **Not tested:** "sticky primary" (read from the primary for N seconds after a write). In this test every read follows a write, so it would always pick the primary, which tells us nothing. `synchronous_commit = remote_apply` was also skipped: the proposal rules it out because it makes every write wait for a replica.

---

## Conclusions
1. **Read-your-writes is solved by LSN routing:** 0 misses in 2,750 reads, including under a forced 2 s lag and under load. Without routing, up to 100% of users wouldn't see their own post.
2. **Replicas take reads off the primary** (CPU 85–98% → ~1%). Lag under load is about 300 ms median, half a second at p95.
3. **Replicas only add read capacity if they add hardware.** On one shared SSD, a second replica made reads ~10% slower, and heavy replica reads even slowed the primary's writes about 100×. On real servers with separate disks this bottleneck wouldn't exist, but this lab can't prove the throughput gain.
4. **Replicas don't help writes** (proposal): every write still goes to the one primary.

## Limits of this step
- Replicas are smaller than the primary (1 GB / 2 CPU vs. 2 GB / 4 CPU), and all three share one SSD and 8 CPU cores.
- No PgBouncer in front of the replicas: with 32 clients it isn't needed, and Step 3 showed it doesn't add throughput.
- Failover (promoting a replica when the primary dies) is out of scope, as the proposal says: use Patroni or a managed service.
- The read-your-writes tests added about 4,200 posts with the body `ryw test N`.

## Raw files (`raw/step4/`)
| Folder or file | What |
|---|---|
| `clone_times.txt` | Replica cloning time |
| `A_{one_node,replicas}_r{1,2}/` | 1 node vs. 2 replicas |
| `B_{1,2}_replica_r{1,2}/` | 1 vs. 2 replicas, same size |
| `C_read_your_writes/results.txt` | All read-your-writes runs |

Each run folder has `summary.txt` (read TPS and p95, real write time), `reads.out` and `writes.out` (pgbench), and `samples.csv` (every 5 s: CPU and memory per node, replay lag, lag in bytes, available host RAM).
