\set uid random(1, 1000000)
SELECT p.id, p.user_id, p.body, p.created_at
FROM follows f
CROSS JOIN LATERAL (
  SELECT id, user_id, body, created_at
  FROM posts
  WHERE user_id = f.followee_id AND NOT is_deleted
  ORDER BY created_at DESC
  LIMIT 30
) p
WHERE f.follower_id = :uid
ORDER BY p.created_at DESC
LIMIT 30;
