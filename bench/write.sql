\set uid random(1, 1000000)
INSERT INTO posts (user_id, body) VALUES (:uid, 'hello from ' || :uid);
