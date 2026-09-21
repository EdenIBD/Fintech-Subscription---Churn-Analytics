\set ON_ERROR_STOP on

WITH comparison_users AS (
    SELECT
        user_id,
        CASE WHEN churn_timestamp IS NULL THEN 'retained' ELSE 'churned' END AS customer_group,
        COALESCE(churn_timestamp, TIMESTAMP '2025-12-31 23:59:59') AS cutoff_timestamp
    FROM analytics.v_paid_lifecycle
    WHERE (churn_timestamp IS NOT NULL AND paid_start_timestamp <= churn_timestamp - INTERVAL '90 days')
       OR (churn_timestamp IS NULL AND paid_start_timestamp <= TIMESTAMP '2025-10-02')
),
transaction_features AS (
    SELECT
        c.user_id,
        COUNT(t.transaction_id) FILTER (
            WHERE t.transaction_timestamp >= c.cutoff_timestamp - INTERVAL '90 days'
        ) AS transaction_count_90d,
        COALESCE(SUM(t.amount_eur) FILTER (
            WHERE t.status = 'successful'
              AND t.transaction_timestamp >= c.cutoff_timestamp - INTERVAL '90 days'
        ), 0) AS successful_volume_eur_90d,
        COUNT(t.transaction_id) FILTER (
            WHERE t.status = 'failed'
              AND t.transaction_timestamp >= c.cutoff_timestamp - INTERVAL '90 days'
        ) AS failed_transaction_count_90d,
        COUNT(t.transaction_id) FILTER (
            WHERE t.transaction_timestamp >= c.cutoff_timestamp - INTERVAL '30 days'
              AND t.status = 'successful'
        ) AS transaction_count_last_30d,
        COUNT(t.transaction_id) FILTER (
            WHERE t.transaction_timestamp >= c.cutoff_timestamp - INTERVAL '60 days'
              AND t.transaction_timestamp < c.cutoff_timestamp - INTERVAL '30 days'
              AND t.status = 'successful'
        ) AS transaction_count_previous_30d,
        MAX(t.transaction_timestamp) AS last_transaction_timestamp
    FROM comparison_users AS c
    LEFT JOIN core.transactions AS t
      ON t.user_id = c.user_id
     AND t.transaction_timestamp < c.cutoff_timestamp
    GROUP BY c.user_id
),
usage_features AS (
    SELECT
        c.user_id,
        COUNT(DISTINCT f.feature_name) FILTER (
            WHERE f.feature_name IN ('rewards', 'international_transfers', 'airport_lounge')
              AND f.usage_timestamp >= c.cutoff_timestamp - INTERVAL '90 days'
        ) AS distinct_paid_benefits_used_90d,
        MAX(f.usage_timestamp) AS last_feature_timestamp
    FROM comparison_users AS c
    LEFT JOIN core.feature_usage AS f
      ON f.user_id = c.user_id
     AND f.usage_timestamp < c.cutoff_timestamp
    GROUP BY c.user_id
),
user_features AS (
    SELECT
        c.customer_group,
        c.user_id,
        t.transaction_count_90d,
        t.successful_volume_eur_90d,
        t.failed_transaction_count_90d,
        EXTRACT(DAY FROM c.cutoff_timestamp - GREATEST(
            COALESCE(t.last_transaction_timestamp, TIMESTAMP '1900-01-01'),
            COALESCE(u.last_feature_timestamp, TIMESTAMP '1900-01-01')
        )) AS days_since_last_activity,
        u.distinct_paid_benefits_used_90d,
        t.transaction_count_last_30d - t.transaction_count_previous_30d
            AS recent_successful_transaction_count_change
    FROM comparison_users AS c
    JOIN transaction_features AS t USING (user_id)
    JOIN usage_features AS u USING (user_id)
)
SELECT
    customer_group,
    COUNT(*) AS customers,
    ROUND(AVG(transaction_count_90d), 2) AS avg_transactions_90d,
    ROUND(AVG(successful_volume_eur_90d), 2) AS avg_successful_volume_eur_90d,
    ROUND(AVG(failed_transaction_count_90d), 2) AS avg_failed_transactions_90d,
    ROUND(AVG(days_since_last_activity), 2) AS avg_days_since_last_activity,
    ROUND(AVG(distinct_paid_benefits_used_90d), 2) AS avg_distinct_paid_benefits_used_90d,
    ROUND(AVG(recent_successful_transaction_count_change), 2)
        AS avg_recent_successful_transaction_count_change,
    PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY transaction_count_90d)
        AS median_transactions_90d
FROM user_features
GROUP BY customer_group
ORDER BY customer_group;
