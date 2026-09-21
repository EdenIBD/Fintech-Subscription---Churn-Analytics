\set ON_ERROR_STOP on

WITH months AS (
    SELECT GENERATE_SERIES(
        DATE_TRUNC('month', MIN(signup_timestamp)),
        DATE '2025-12-01',
        INTERVAL '1 month'
    )::DATE AS month_start
    FROM core.users
),
activities AS (
    SELECT user_id, DATE_TRUNC('month', transaction_timestamp)::DATE AS month_start
    FROM core.transactions
    UNION
    SELECT user_id, DATE_TRUNC('month', usage_timestamp)::DATE
    FROM core.feature_usage
),
mau AS (
    SELECT month_start, COUNT(DISTINCT user_id) AS monthly_active_users
    FROM activities
    GROUP BY month_start
),
paid_at_month_end AS (
    SELECT m.month_start, COUNT(DISTINCT st.user_id) AS active_paid_subscribers
    FROM months AS m
    JOIN analytics.v_subscription_timeline AS st
      ON st.valid_from < m.month_start + INTERVAL '1 month'
     AND (st.valid_to IS NULL OR st.valid_to >= m.month_start + INTERVAL '1 month')
    JOIN core.plans AS p ON p.plan_id = st.plan_id AND p.plan_level > 0
    GROUP BY m.month_start
),
new_paid AS (
    SELECT DATE_TRUNC('month', paid_start_timestamp)::DATE AS month_start,
           COUNT(*) AS new_paid_subscribers
    FROM analytics.v_paid_lifecycle
    GROUP BY 1
),
subscription_revenue AS (
    SELECT DATE_TRUNC('month', event_timestamp)::DATE AS month_start,
           SUM(net_subscription_revenue_eur) AS net_subscription_revenue_eur
    FROM analytics.v_subscription_charges
    GROUP BY 1
),
transaction_kpis AS (
    SELECT
        DATE_TRUNC('month', transaction_timestamp)::DATE AS month_start,
        ROUND(100.0 * COUNT(*) FILTER (WHERE status = 'successful') / COUNT(*), 2)
            AS transaction_success_rate_pct,
        SUM(amount_eur) FILTER (WHERE status = 'successful') AS successful_volume_eur
    FROM core.transactions
    GROUP BY 1
)
SELECT
    m.month_start,
    COALESCE(a.monthly_active_users, 0) AS monthly_active_users,
    COALESCE(p.active_paid_subscribers, 0) AS active_paid_subscribers,
    COALESCE(n.new_paid_subscribers, 0) AS new_paid_subscribers,
    COALESCE(r.net_subscription_revenue_eur, 0)::NUMERIC(14, 2)
        AS monthly_subscription_revenue_eur,
    ROUND(
        COALESCE(r.net_subscription_revenue_eur, 0)
        / NULLIF(p.active_paid_subscribers, 0), 2
    ) AS average_revenue_per_paid_user_eur,
    COALESCE(t.transaction_success_rate_pct, 0) AS transaction_success_rate_pct,
    COALESCE(t.successful_volume_eur, 0)::NUMERIC(16, 2) AS successful_transaction_volume_eur
FROM months AS m
LEFT JOIN mau AS a USING (month_start)
LEFT JOIN paid_at_month_end AS p USING (month_start)
LEFT JOIN new_paid AS n USING (month_start)
LEFT JOIN subscription_revenue AS r USING (month_start)
LEFT JOIN transaction_kpis AS t USING (month_start)
ORDER BY m.month_start;

