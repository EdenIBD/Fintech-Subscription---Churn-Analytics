\set ON_ERROR_STOP on

WITH funnel AS (
    SELECT * FROM analytics.v_user_journey
)
SELECT
    COUNT(*) AS signups,
    COUNT(verification_timestamp) AS verified,
    COUNT(first_deposit_timestamp) AS first_deposits,
    COUNT(first_successful_transaction) AS first_successful_transactions,
    COUNT(first_paid_subscription) AS first_paid_subscriptions,
    ROUND(100.0 * COUNT(verification_timestamp) / COUNT(*), 2) AS signup_to_verification_pct,
    ROUND(100.0 * COUNT(first_deposit_timestamp) / NULLIF(COUNT(verification_timestamp), 0), 2)
        AS verification_to_deposit_pct,
    ROUND(100.0 * COUNT(first_successful_transaction) / NULLIF(COUNT(first_deposit_timestamp), 0), 2)
        AS deposit_to_transaction_pct,
    ROUND(100.0 * COUNT(first_paid_subscription) / NULLIF(COUNT(first_successful_transaction), 0), 2)
        AS transaction_to_paid_pct,
    ROUND(100.0 * COUNT(first_paid_subscription) / COUNT(*), 2) AS overall_paid_conversion_pct,
    PERCENTILE_CONT(0.5) WITHIN GROUP (
        ORDER BY verification_timestamp - signup_timestamp
    ) FILTER (WHERE verification_timestamp IS NOT NULL) AS median_signup_to_verification,
    PERCENTILE_CONT(0.5) WITHIN GROUP (
        ORDER BY first_deposit_timestamp - verification_timestamp
    ) FILTER (WHERE first_deposit_timestamp IS NOT NULL) AS median_verification_to_deposit,
    PERCENTILE_CONT(0.5) WITHIN GROUP (
        ORDER BY first_successful_transaction - first_deposit_timestamp
    ) FILTER (WHERE first_successful_transaction IS NOT NULL) AS median_deposit_to_transaction,
    PERCENTILE_CONT(0.5) WITHIN GROUP (
        ORDER BY first_paid_subscription - first_successful_transaction
    ) FILTER (WHERE first_paid_subscription IS NOT NULL) AS median_transaction_to_paid
FROM funnel;

WITH funnel AS (
    SELECT
        *,
        TO_CHAR(DATE_TRUNC('month', signup_timestamp), 'YYYY-MM') AS signup_cohort
    FROM analytics.v_user_journey
),
breakdowns AS (
    SELECT
        CASE
            WHEN GROUPING(signup_cohort) = 0 THEN 'signup_cohort'
            WHEN GROUPING(country) = 0 THEN 'country'
            ELSE 'acquisition_channel'
        END AS dimension,
        COALESCE(signup_cohort, country, acquisition_channel) AS segment,
        COUNT(*) AS signups,
        COUNT(verification_timestamp) AS verified,
        COUNT(first_deposit_timestamp) AS deposited,
        COUNT(first_successful_transaction) AS transacted,
        COUNT(first_paid_subscription) AS paid
    FROM funnel
    GROUP BY GROUPING SETS ((signup_cohort), (country), (acquisition_channel))
)
SELECT
    *,
    ROUND(100.0 * verified / signups, 2) AS verification_rate_pct,
    ROUND(100.0 * paid / signups, 2) AS overall_paid_conversion_pct
FROM breakdowns
ORDER BY dimension, segment;

