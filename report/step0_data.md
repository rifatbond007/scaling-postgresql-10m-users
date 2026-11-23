# Step 0: Lab and data

[← Summary](00_SUMMARY.md) · Next: [Step 1 →](step1_baseline.md)

## What was built
- **One PostgreSQL 16 server** in Docker (`docker/single.yml`).
- **Three tables:** `users`, `follows`, `posts` (`sql/schema.sql`).
- **No index on `posts`** other than the primary key. That's deliberate: this is the "before" state.

## Data loaded (`sql/seed.sql`)

| Table | Rows | Size on disk | Load time |
|---|---:|---:|---:|
| users | 1,000,000 | 79 MB | 2 s |
| follows | 19,999,767 | 1,767 MB | 3 min 16 s |
| posts | 10,000,000 | 1,423 MB | 56 s |
| **Total** | | **3.3 GB** | **about 5 min** |

## Shape of the data
- Every user follows **exactly 20** random people, so there are no popular users yet. Celebrities come in Step 8.
- Each user has **about 10 posts** on average, spread over the last 12 months.
- **0.5% of posts (50,000) are marked deleted.** This is added to the proposal so the partial index in Step 2 has something to skip.

Raw log: `raw/step0/seed.log`
