\set ON_ERROR_STOP on

CREATE TEMP TABLE test_results (
    test_name TEXT PRIMARY KEY,
    actual TEXT NOT NULL,
    expected TEXT NOT NULL
);

CREATE TEMP VIEW retention_rates AS
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
)
SELECT
    c.cohort_month,
    a.month_number,
    COUNT(*) FILTER (
        WHERE c.churn_timestamp IS NULL
           OR c.churn_timestamp > c.paid_start_timestamp + a.month_number * INTERVAL '1 month'
    )::NUMERIC / COUNT(*) AS retention_rate
FROM cohorts AS c
CROSS JOIN ages AS a
WHERE c.paid_start_timestamp + a.month_number * INTERVAL '1 month'
      <= TIMESTAMP '2025-12-31 23:59:59'
GROUP BY c.cohort_month, a.month_number;

INSERT INTO test_results
SELECT 'user row count', COUNT(*)::TEXT, '15000' FROM core.users
UNION ALL
SELECT 'plan row count', COUNT(*)::TEXT, '5' FROM core.plans
UNION ALL
SELECT 'campaign row count', COUNT(*)::TEXT, '6' FROM core.marketing_campaigns
UNION ALL
SELECT 'subscription event row count', COUNT(*)::TEXT, '37483' FROM core.subscription_events
UNION ALL
SELECT 'transaction row count', COUNT(*)::TEXT, '191271' FROM core.transactions
UNION ALL
SELECT 'feature usage row count', COUNT(*)::TEXT, '77792' FROM core.feature_usage
UNION ALL
SELECT 'first paid subscription count', COUNT(*)::TEXT, '4319'
FROM core.subscription_events WHERE event_type = 'subscription_started'
UNION ALL
SELECT 'plan catalogue', STRING_AGG(plan_name || ':' || monthly_price_eur, ',' ORDER BY plan_level),
       'Basic:0.00,Plus:4.99,Premium:9.99,Metal:16.99,Elite:29.99'
FROM core.plans
UNION ALL
SELECT 'fx conversion mismatches', COUNT(*)::TEXT, '0'
FROM core.transactions
WHERE ABS(amount_eur - ROUND(amount_original * fx_rate_to_eur, 2)) > 0.01
UNION ALL
SELECT 'funnel chronology violations', COUNT(*)::TEXT, '0'
FROM analytics.v_user_journey
WHERE (verification_timestamp IS NOT NULL AND verification_timestamp < signup_timestamp)
   OR (first_deposit_timestamp IS NOT NULL AND first_deposit_timestamp < verification_timestamp)
   OR (first_successful_transaction IS NOT NULL AND first_successful_transaction < first_deposit_timestamp)
   OR (first_paid_subscription IS NOT NULL AND first_paid_subscription < first_successful_transaction)
UNION ALL
SELECT 'month zero retention violations', COUNT(*)::TEXT, '0'
FROM retention_rates
WHERE month_number = 0 AND retention_rate <> 1
UNION ALL
SELECT 'retention increase violations', COUNT(*)::TEXT, '0'
FROM (
    SELECT
        retention_rate,
        LAG(retention_rate) OVER (PARTITION BY cohort_month ORDER BY month_number)
            AS previous_rate
    FROM retention_rates
) AS ordered_rates
WHERE retention_rate > previous_rate
UNION ALL
SELECT 'at-risk cancellation count',
       SUM(voluntary_cancellations + involuntary_churn)::TEXT,
       '3272'
FROM analytics.v_monthly_subscription_movements;

SELECT test_name, actual, expected, actual = expected AS passed
FROM test_results
ORDER BY test_name;

DO $$
DECLARE
    failed_tests TEXT;
BEGIN
    SELECT STRING_AGG(test_name, ', ' ORDER BY test_name)
    INTO failed_tests
    FROM test_results
    WHERE actual <> expected;

    IF failed_tests IS NOT NULL THEN
        RAISE EXCEPTION 'Expected-result tests failed: %', failed_tests;
    END IF;
END $$;
