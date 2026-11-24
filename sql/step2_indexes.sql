-- Step 2 (proposal section 04): the indexes, in the order they were tested.
-- Each was benchmarked separately; this file ends in the final state used from Step 3 on.

-- 2.1 composite: equality column first (user_id), then the sort column (created_at)
CREATE INDEX CONCURRENTLY IF NOT EXISTS idx_posts_user_created
  ON posts (user_id, created_at DESC);

-- 2.2 the query rewrite needs no index change: see bench/feed_lateral.sql

-- 2.3 partial: only live posts; replaces the composite index
CREATE INDEX CONCURRENTLY IF NOT EXISTS idx_posts_user_created_live
  ON posts (user_id, created_at DESC)
  WHERE NOT is_deleted;
DROP INDEX CONCURRENTLY IF EXISTS idx_posts_user_created;

-- 2.4 covering: follower count answered from the index alone (Index Only Scan)
CREATE INDEX CONCURRENTLY IF NOT EXISTS idx_follows_followee
  ON follows (followee_id) INCLUDE (follower_id);

VACUUM ANALYZE follows;   -- sets the visibility map so Index Only Scan needs no heap fetches
