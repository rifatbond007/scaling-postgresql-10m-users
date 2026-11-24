-- Step 1: which queries use the most total time (proposal section 03).
-- Run SELECT pg_stat_statements_reset(); right before a benchmark (bench/run.sh does this), then:
SELECT calls,
       round(total_exec_time::numeric, 0)  AS total_ms,
       round(mean_exec_time::numeric, 2)   AS mean_ms,
       round((100 * total_exec_time / sum(total_exec_time) OVER ())::numeric, 1) AS pct,
       left(query, 80) AS query
FROM pg_stat_statements
ORDER BY total_exec_time DESC
LIMIT 10;
