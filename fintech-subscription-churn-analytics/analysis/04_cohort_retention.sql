\set ON_ERROR_STOP on

-- Long form: denominator is everyone who first became paid in the cohort month.
WITH cohorts AS (
    SELECT
        user_id,
        paid_start_timestamp,
        churn_timestamp,
        DATE_TRUNC('month', paid_start_timestamp)::DATE AS cohort_month
    FROM analytics.v_paid_lifecycle
),
ages AS (
    SELECT GENERATE_SERIES(0, 6) AS month_number
),
cohort_sizes AS (
    SELECT cohort_month, COUNT(*) AS cohort_size
    FROM cohorts
    GROUP BY cohort_month
),
retention AS (
    SELECT
        c.cohort_month,
        a.month_number,
        COUNT(*) FILTER (
            WHERE c.churn_timestamp IS NULL
               OR c.churn_timestamp > c.paid_start_timestamp + a.month_number * INTERVAL '1 month'
        ) AS retained_users
    FROM cohorts AS c
    CROSS JOIN ages AS a
    WHERE c.paid_start_timestamp + a.month_number * INTERVAL '1 month'
          <= TIMESTAMP '2025-12-31 23:59:59'
    GROUP BY c.cohort_month, a.month_number
)
SELECT
    r.cohort_month,
    r.month_number,
    s.cohort_size,
    r.retained_users,
    ROUND(100.0 * r.retained_users / s.cohort_size, 2) AS retention_rate_pct
FROM retention AS r
JOIN cohort_sizes AS s USING (cohort_month)
ORDER BY r.cohort_month, r.month_number;

-- Matrix: NULL means the cohort has not had enough observation time.
WITH cohorts AS (
    SELECT
        user_id,
        paid_start_timestamp,
        churn_timestamp,
        DATE_TRUNC('month', paid_start_timestamp)::DATE AS cohort_month
    FROM analytics.v_paid_lifecycle
),
ages AS (
    SELECT GENERATE_SERIES(0, 6) AS month_number
),
rates AS (
    SELECT
        c.cohort_month,
        a.month_number,
        ROUND(100.0 * COUNT(*) FILTER (
            WHERE c.churn_timestamp IS NULL
               OR c.churn_timestamp > c.paid_start_timestamp + a.month_number * INTERVAL '1 month'
        ) / COUNT(*), 2) AS retention_rate_pct
    FROM cohorts AS c
    CROSS JOIN ages AS a
    WHERE c.paid_start_timestamp + a.month_number * INTERVAL '1 month'
          <= TIMESTAMP '2025-12-31 23:59:59'
    GROUP BY c.cohort_month, a.month_number
)
SELECT
    cohort_month,
    MAX(retention_rate_pct) FILTER (WHERE month_number = 0) AS month_0,
    MAX(retention_rate_pct) FILTER (WHERE month_number = 1) AS month_1,
    MAX(retention_rate_pct) FILTER (WHERE month_number = 2) AS month_2,
    MAX(retention_rate_pct) FILTER (WHERE month_number = 3) AS month_3,
    MAX(retention_rate_pct) FILTER (WHERE month_number = 4) AS month_4,
    MAX(retention_rate_pct) FILTER (WHERE month_number = 5) AS month_5,
    MAX(retention_rate_pct) FILTER (WHERE month_number = 6) AS month_6
FROM rates
GROUP BY cohort_month
ORDER BY cohort_month;
