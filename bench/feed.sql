\set uid random(1, 1000000)
SELECT p.id, p.user_id, p.body, p.created_at
FROM follows f
JOIN posts p ON p.user_id = f.followee_id
WHERE f.follower_id = :uid AND NOT p.is_deleted
ORDER BY p.created_at DESC
LIMIT 30;
