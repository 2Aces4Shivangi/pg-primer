SELECT CURRENT_TIMESTAMP - query_start AS running_time, *
FROM pg_stat_activity
WHERE state = 'idle in transaction'
ORDER BY running_time DESC;
