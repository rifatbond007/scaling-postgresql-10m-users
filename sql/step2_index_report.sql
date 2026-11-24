-- Step 2: index sizes and how often each index was used (idx_scan = 0 means unused).
SELECT relname AS table_name, indexrelname AS index_name,
       pg_size_pretty(pg_relation_size(indexrelid)) AS size,
       idx_scan
FROM pg_stat_user_indexes
ORDER BY idx_scan, pg_relation_size(indexrelid) DESC;
