# Step 2: Indexes and query rewrite

[← Step 1](step1_baseline.md) · [Summary](00_SUMMARY.md) · Next: [Step 3 →](step3_pgbouncer.md)

Same test as Step 1: 32 clients, 90% feed / 10% write, 120 s. **One change at a time.**

## Results

| # | Change | TPS | Feed p95 | One feed query | Verdict |
|---|---|---:|---:|---:|---|
| | Baseline | 0.81 | 55,788 ms | 2,131 ms | |
| 2a | Index on `posts(user_id, created_at DESC)` | **770** | **100 ms** | **2.9 ms** | ✅ **The big win** |
| 2b | Rewrite feed with `LATERAL` | about +7% | 78 ms | 3.4 ms | ➖ Within noise |
| 2c | Partial index (skips deleted) + covering index on follows | 1,353 | 67 ms | 18 ms (cold) | ➖ No real gain here |

---

## 2a: Composite index ✅

```sql
CREATE INDEX CONCURRENTLY idx_posts_user_created ON posts (user_id, created_at DESC);
```

| | Before | After |
|---|---:|---:|
| Plan | Seq Scan, all 10M rows | Index Scan, about 9 rows per followee |
| Pages read | 154,006 | 275 |
| One query | 2,131 ms | **2.9 ms** |
| Throughput | 0.81 TPS | **770 TPS** |
| Feed p95 | 55,788 ms | **100 ms** |

Index size 301 MB, built in 9 seconds.

## 2b: Query rewrite with LATERAL ➖

The first run showed **+42%**, which looked great, so I repeated the comparison. **Most of it was the cache warming up**, not the rewrite.

| Run order | Query | TPS | Feed p95 |
|---|---|---:|---:|
| 1 | Original | 949 | 95 ms |
| 2 | Lateral | 1,213 | 78 ms |
| 3 | Original (same query as run 1) | 1,130 | 86 ms |

The original query alone sped up from 949 to 1,130 TPS with no change at all. The lateral version's real gain is **about 7%**.

**Why so small:** each user has only about 9 posts, so "take the top 30 per followee" never cuts anything off. It should matter for users with thousands of posts. **Retest in Step 8 with celebrities.**

## 2c: Partial and covering index ➖

```sql
CREATE INDEX CONCURRENTLY idx_posts_user_created_live
  ON posts (user_id, created_at DESC) WHERE NOT is_deleted;     -- replaces 2a's index
CREATE INDEX CONCURRENTLY idx_follows_followee
  ON follows (followee_id) INCLUDE (follower_id);
```

| Index | Size | Result |
|---|---:|---|
| Partial (skips deleted) | 302 MB (vs. 301 MB) | Not smaller: only 0.5% of posts are deleted. Kept because it's never worse. |
| Covering on follows | **602 MB** | Follower count reads only the index (Heap Fetches 0) in **0.6 ms**. Costly in space. |

## Do indexes slow down writes?

Writes only, 32 clients, 60 s each, after resetting the database state (VACUUM and CHECKPOINT):

| Posts index | TPS | Write p95 |
|---|---:|---:|
| With | 3,214 | 11.8 ms |
| Without | 3,227 | 11.7 ms |
| With (repeat) | 3,223 | 11.9 ms |

**No measurable difference.** Each insert is its own transaction, so the time goes into flushing each commit to disk, not into updating the index.

⚠️ Without that reset, the same test swung between **3,200 and 12,800 TPS** depending on checkpoint timing.

---

## Conclusions
1. **One index did almost all the work:** about 950× throughput.
2. **The rewrite and partial index barely matter on this data.** Revisit in Step 8.
3. **The covering index works but is expensive** (602 MB). Only worth it if the follower count is a hot query. **Checked later** (`sql/step2_index_report.sql`, after the Step 3 benchmarks): `idx_follows_followee` had **0 scans**, since the feed workload never counts followers. In this workload it's dead weight: 602 MB that slows follow/unfollow writes.
4. **Laptop benchmarks are noisy.** From Step 3 on, the cache is preloaded (`pg_prewarm`) before every run.

## Current database state (carried into Step 3)
- Indexes: `idx_posts_user_created_live` (partial), `idx_follows_followee` (covering), plus the primary keys.
- Feed query used from now on: `bench/feed_lateral.sql`

## Raw files
`raw/step2/`: one folder per run (`a_composite`, `b_recheck_1_original`, …, `write_cost/`), each with `pgbench.out`, `percentiles.txt` and the EXPLAIN plan where relevant.
