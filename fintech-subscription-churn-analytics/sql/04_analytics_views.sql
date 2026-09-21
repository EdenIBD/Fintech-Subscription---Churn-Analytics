\set ON_ERROR_STOP on

CREATE OR REPLACE VIEW analytics.v_user_journey AS
SELECT
    u.user_id,
    u.signup_timestamp,
    u.country,
    u.acquisition_channel,
    u.acquisition_campaign_id,
    u.verification_timestamp,
    u.first_deposit_timestamp,
    first_tx.first_successful_transaction,
    first_paid.first_paid_subscription
FROM core.users AS u
LEFT JOIN LATERAL (
    SELECT MIN(t.transaction_timestamp) AS first_successful_transaction
    FROM core.transactions AS t
    WHERE t.user_id = u.user_id
      AND t.status = 'successful'
      AND u.first_deposit_timestamp IS NOT NULL
      AND t.transaction_timestamp >= u.first_deposit_timestamp
) AS first_tx ON true
LEFT JOIN LATERAL (
    SELECT MIN(se.event_timestamp) AS first_paid_subscription
    FROM core.subscription_events AS se
    JOIN core.plans AS p ON p.plan_id = se.new_plan_id
    WHERE se.user_id = u.user_id
      AND se.event_type = 'subscription_started'
      AND p.plan_level > 0
      AND first_tx.first_successful_transaction IS NOT NULL
      AND se.event_timestamp >= first_tx.first_successful_transaction
) AS first_paid ON true;

CREATE OR REPLACE VIEW analytics.v_subscription_timeline AS
WITH state_changes AS (
    SELECT
        se.event_id,
        se.user_id,
        se.event_timestamp AS valid_from,
        LEAD(se.event_timestamp) OVER (
            PARTITION BY se.user_id
            ORDER BY se.event_timestamp, se.event_id
        ) AS valid_to,
        se.new_plan_id AS plan_id,
        se.event_type,
        se.event_reason
    FROM core.subscription_events AS se
    WHERE se.event_type <> 'payment_failed'
)
SELECT * FROM state_changes;

CREATE OR REPLACE VIEW analytics.v_paid_lifecycle AS
SELECT
    se.user_id,
    MIN(se.event_timestamp) FILTER (
        WHERE se.event_type = 'subscription_started'
    ) AS paid_start_timestamp,
    MIN(se.event_timestamp) FILTER (
        WHERE se.event_type = 'cancelled'
    ) AS churn_timestamp,
    BOOL_OR(
        se.event_type = 'cancelled' AND se.event_reason = 'payment_failure'
    ) AS involuntary_churn
FROM core.subscription_events AS se
GROUP BY se.user_id;

CREATE OR REPLACE VIEW analytics.v_subscription_charges AS
WITH billable_events AS (
    SELECT
        se.event_id,
        se.user_id,
        se.event_timestamp,
        se.new_plan_id AS plan_id,
        ROW_NUMBER() OVER (
            PARTITION BY se.user_id
            ORDER BY se.event_timestamp, se.event_id
        ) AS billing_number
    FROM core.subscription_events AS se
    JOIN core.plans AS p ON p.plan_id = se.new_plan_id
    WHERE se.event_type IN ('subscription_started', 'renewed', 'upgraded', 'downgraded')
      AND p.plan_level > 0
)
SELECT
    b.event_id,
    b.user_id,
    b.event_timestamp,
    b.plan_id,
    b.billing_number,
    p.monthly_price_eur AS gross_revenue_eur,
    ROUND(
        p.monthly_price_eur
        * CASE
            WHEN b.billing_number <= COALESCE(c.discount_months, 0)
                THEN COALESCE(c.discount_percentage, 0) / 100
            ELSE 0
          END,
        2
    ) AS campaign_discount_eur,
    p.monthly_price_eur - ROUND(
        p.monthly_price_eur
        * CASE
            WHEN b.billing_number <= COALESCE(c.discount_months, 0)
                THEN COALESCE(c.discount_percentage, 0) / 100
            ELSE 0
          END,
        2
    ) AS net_subscription_revenue_eur
FROM billable_events AS b
JOIN core.plans AS p ON p.plan_id = b.plan_id
JOIN core.users AS u ON u.user_id = b.user_id
LEFT JOIN core.marketing_campaigns AS c
    ON c.campaign_id = u.acquisition_campaign_id;

CREATE OR REPLACE VIEW analytics.v_monthly_subscription_movements AS
WITH months AS (
    SELECT GENERATE_SERIES(
        DATE '2023-01-01', DATE '2025-12-01', INTERVAL '1 month'
    )::DATE AS month_start
),
movements AS (
    SELECT
        DATE_TRUNC('month', event_timestamp)::DATE AS month_start,
        COUNT(*) FILTER (WHERE event_type = 'subscription_started') AS new_subscriptions,
        COUNT(*) FILTER (WHERE event_type = 'renewed') AS renewals,
        COUNT(*) FILTER (WHERE event_type = 'upgraded') AS upgrades,
        COUNT(*) FILTER (WHERE event_type = 'downgraded') AS downgrades
    FROM core.subscription_events
    GROUP BY 1
),
paid_at_start AS (
    SELECT m.month_start, st.user_id
    FROM months AS m
    JOIN analytics.v_subscription_timeline AS st
      ON st.valid_from < m.month_start
     AND (st.valid_to IS NULL OR st.valid_to >= m.month_start)
    JOIN core.plans AS p ON p.plan_id = st.plan_id AND p.plan_level > 0
),
cancellations AS (
    SELECT
        p.month_start,
        COUNT(*) FILTER (WHERE se.event_reason <> 'payment_failure')
            AS voluntary_cancellations,
        COUNT(*) FILTER (WHERE se.event_reason = 'payment_failure')
            AS involuntary_churn
    FROM paid_at_start AS p
    JOIN core.subscription_events AS se
      ON se.user_id = p.user_id
     AND se.event_type = 'cancelled'
     AND se.event_timestamp >= p.month_start
     AND se.event_timestamp < p.month_start + INTERVAL '1 month'
    GROUP BY p.month_start
),
paid_population AS (
    SELECT month_start, COUNT(DISTINCT user_id) AS active_paid_at_month_start
    FROM paid_at_start
    GROUP BY month_start
)
SELECT
    m.month_start,
    COALESCE(p.active_paid_at_month_start, 0) AS active_paid_at_month_start,
    COALESCE(v.new_subscriptions, 0) AS new_subscriptions,
    COALESCE(v.renewals, 0) AS renewals,
    COALESCE(v.upgrades, 0) AS upgrades,
    COALESCE(v.downgrades, 0) AS downgrades,
    COALESCE(c.voluntary_cancellations, 0) AS voluntary_cancellations,
    COALESCE(c.involuntary_churn, 0) AS involuntary_churn,
    ROUND(
        100.0 * (
            COALESCE(c.voluntary_cancellations, 0) + COALESCE(c.involuntary_churn, 0)
        ) / NULLIF(p.active_paid_at_month_start, 0),
        2
    ) AS paid_subscription_churn_rate_pct
FROM months AS m
LEFT JOIN movements AS v USING (month_start)
LEFT JOIN paid_population AS p USING (month_start)
LEFT JOIN cancellations AS c USING (month_start);
