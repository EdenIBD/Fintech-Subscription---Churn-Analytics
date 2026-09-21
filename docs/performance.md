# Performance comparison

Measured on 2026-09-19 with PostgreSQL 16 in the repository's Docker container. Timings depend on hardware and cache state.

## Query pattern

The query reconstructs the latest subscription state for 3,000 users at the analysis cutoff. This is the central operation behind point-in-time subscriber metrics.

```sql
SELECT COUNT(*) FILTER (WHERE p.plan_level > 0) AS active_paid
FROM core.users AS u
LEFT JOIN LATERAL (
    SELECT se.new_plan_id
    FROM core.subscription_events AS se
    WHERE se.user_id = u.user_id
      AND se.event_type <> 'payment_failed'
      AND se.event_timestamp <= TIMESTAMP '2025-12-31 23:59:59'
    ORDER BY se.event_timestamp DESC
    LIMIT 1
) AS latest ON true
LEFT JOIN core.plans AS p ON p.plan_id = latest.new_plan_id
WHERE u.user_id <= 3000;
```

## Before the index

`EXPLAIN (ANALYZE, BUFFERS)` measured **3,210.437 ms** and **1,224,934 shared-buffer hits**. The important part of the actual plan was:

```text
Aggregate (actual time=3210.377..3210.378 rows=1 loops=1)
  Buffers: shared hit=1224934
  -> Nested Loop Left Join (actual time=1.738..3210.137 rows=3000 loops=1)
       -> Index Only Scan using users_pkey (actual time=0.013..0.695 rows=3000 loops=1)
       -> Subquery Scan on latest (actual time=1.067..1.067 rows=0 loops=3000)
            -> Limit (actual time=1.067..1.067 rows=0 loops=3000)
                 -> Sort (actual time=1.067..1.067 rows=0 loops=3000)
                      Sort Key: se.event_timestamp DESC
                      -> Seq Scan on subscription_events se
                           (actual time=0.782..1.066 rows=2 loops=3000)
                           Rows Removed by Filter: 37481
Planning Time: 1.012 ms
Execution Time: 3210.437 ms
```

The database scanned nearly all 37,483 subscription events once for each user.

## After the index

`sql/05_indexes.sql` adds:

```sql
CREATE INDEX idx_subscription_events_user_time
    ON core.subscription_events (user_id, event_timestamp DESC)
    INCLUDE (event_type, old_plan_id, new_plan_id, event_reason);
```

The same query measured **2.685 ms** and **9,941 shared-buffer hits/read requests** (`9,873` hits and `68` reads), about **1,196× faster** in this run.

```text
Aggregate (actual time=2.637..2.638 rows=1 loops=1)
  Buffers: shared hit=9873 read=68
  -> Nested Loop Left Join (actual time=0.034..2.557 rows=3000 loops=1)
       -> Index Only Scan using users_pkey (actual time=0.011..0.235 rows=3000 loops=1)
       -> Limit (actual time=0.001..0.001 rows=0 loops=3000)
            -> Index Only Scan using idx_subscription_events_user_time
                 (actual time=0.000..0.000 rows=0 loops=3000)
                 Index Cond: user_id and event_timestamp cutoff
                 Heap Fetches: 892
Planning Time: 0.903 ms
Execution Time: 2.685 ms
```

This large ratio comes from removing a deliberately expensive repeated scan; it is not a general database-speed claim. The index matches the lookup order directly, and its value should grow with a longer event history.

