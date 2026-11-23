CREATE EXTENSION IF NOT EXISTS pg_stat_statements;

CREATE TABLE users (
  id          bigint PRIMARY KEY,
  handle      text NOT NULL,
  created_at  timestamptz NOT NULL DEFAULT now()
);

CREATE TABLE follows (
  follower_id bigint NOT NULL,
  followee_id bigint NOT NULL,
  created_at  timestamptz NOT NULL DEFAULT now(),
  PRIMARY KEY (follower_id, followee_id)
);

CREATE TABLE posts (
  id          bigserial PRIMARY KEY,
  user_id     bigint NOT NULL,
  body        text NOT NULL,
  is_deleted  boolean NOT NULL DEFAULT false,
  created_at  timestamptz NOT NULL DEFAULT now()
);
-- Intentionally no index on posts(user_id) or posts(created_at): this is the baseline.
