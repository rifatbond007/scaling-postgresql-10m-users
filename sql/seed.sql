\timing on
SET synchronous_commit = off;

INSERT INTO users
SELECT g, 'user' || g, now() - (random() * interval '700 days')
FROM generate_series(1, 1000000) g;

INSERT INTO follows (follower_id, followee_id)
SELECT DISTINCT u, ((random() * 999999)::int + 1)
FROM generate_series(1, 1000000) u, generate_series(1, 20) k
ON CONFLICT DO NOTHING;
DELETE FROM follows WHERE follower_id = followee_id;

INSERT INTO posts (user_id, body, created_at)
SELECT ((random() * 999999)::int + 1),
       md5(random()::text) || md5(random()::text),
       now() - (random() * interval '365 days')
FROM generate_series(1, 10000000);

-- ~0.5% soft-deleted posts so the partial index in Step 2 has something to skip
UPDATE posts SET is_deleted = true WHERE id % 200 = 0;

VACUUM ANALYZE;

SELECT 'users' t, count(*) FROM users
UNION ALL SELECT 'follows', count(*) FROM follows
UNION ALL SELECT 'posts', count(*) FROM posts;
SELECT pg_size_pretty(pg_database_size('app')) AS db_size;
