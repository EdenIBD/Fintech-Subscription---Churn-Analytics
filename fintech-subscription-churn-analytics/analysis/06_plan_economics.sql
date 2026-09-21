\set ON_ERROR_STOP on

WITH subscription_components AS (
    SELECT
        u.acquisition_channel,
        c.plan_id,
        SUM(c.gross_revenue_eur) AS gross_subscription_revenue_eur,
        0::NUMERIC AS estimated_transaction_revenue_eur,
        SUM(c.campaign_discount_eur) AS campaign_discounts_eur,
        SUM(CASE c.plan_id WHEN 2 THEN 0.75 WHEN 3 THEN 2.50 WHEN 4 THEN 6.50 WHEN 5 THEN 10.50 ELSE 0 END)
            AS estimated_benefit_costs_eur
    FROM analytics.v_subscription_charges AS c
    JOIN core.users AS u USING (user_id)
    GROUP BY u.acquisition_channel, c.plan_id
),
transaction_components AS (
    SELECT
        u.acquisition_channel,
        COALESCE(state.plan_id, 1) AS plan_id,
        0::NUMERIC AS gross_subscription_revenue_eur,
        SUM(CASE t.transaction_type
            WHEN 'card_purchase' THEN t.amount_eur * 0.0020
            WHEN 'international_transfer' THEN t.amount_eur * 0.0045
            WHEN 'fx_exchange' THEN t.amount_eur * 0.0015
            WHEN 'cash_withdrawal' THEN t.amount_eur * 0.0010
            ELSE t.amount_eur * 0.0005
        END) AS estimated_transaction_revenue_eur,
        0::NUMERIC AS campaign_discounts_eur,
        SUM(CASE
            WHEN t.transaction_type = 'card_purchase' AND COALESCE(state.plan_id, 1) = 3
                THEN t.amount_eur * 0.003
            WHEN t.transaction_type = 'card_purchase' AND COALESCE(state.plan_id, 1) IN (4, 5)
                THEN t.amount_eur * 0.006
            ELSE 0
        END) AS estimated_benefit_costs_eur
    FROM core.transactions AS t
    JOIN core.users AS u USING (user_id)
    LEFT JOIN LATERAL (
        SELECT st.plan_id
        FROM analytics.v_subscription_timeline AS st
        WHERE st.user_id = t.user_id
          AND st.valid_from <= t.transaction_timestamp
          AND (st.valid_to IS NULL OR st.valid_to > t.transaction_timestamp)
        ORDER BY st.valid_from DESC
        LIMIT 1
    ) AS state ON true
    WHERE t.status = 'successful'
    GROUP BY u.acquisition_channel, COALESCE(state.plan_id, 1)
),
usage_components AS (
    SELECT
        u.acquisition_channel,
        COALESCE(state.plan_id, 1) AS plan_id,
        0::NUMERIC AS gross_subscription_revenue_eur,
        0::NUMERIC AS estimated_transaction_revenue_eur,
        0::NUMERIC AS campaign_discounts_eur,
        SUM(CASE f.feature_name
            WHEN 'airport_lounge' THEN 18.00
            WHEN 'rewards' THEN 0.35
            WHEN 'international_transfers' THEN 0.20
            WHEN 'savings' THEN 0.05
            ELSE 0
        END) AS estimated_benefit_costs_eur
    FROM core.feature_usage AS f
    JOIN core.users AS u USING (user_id)
    LEFT JOIN LATERAL (
        SELECT st.plan_id
        FROM analytics.v_subscription_timeline AS st
        WHERE st.user_id = f.user_id
          AND st.valid_from <= f.usage_timestamp
          AND (st.valid_to IS NULL OR st.valid_to > f.usage_timestamp)
        ORDER BY st.valid_from DESC
        LIMIT 1
    ) AS state ON true
    GROUP BY u.acquisition_channel, COALESCE(state.plan_id, 1)
),
all_components AS (
    SELECT * FROM subscription_components
    UNION ALL SELECT * FROM transaction_components
    UNION ALL SELECT * FROM usage_components
)
SELECT
    p.plan_name,
    c.acquisition_channel,
    ROUND(SUM(c.gross_subscription_revenue_eur), 2) AS gross_subscription_revenue_eur,
    ROUND(SUM(c.estimated_transaction_revenue_eur), 2) AS estimated_transaction_revenue_eur,
    ROUND(SUM(c.campaign_discounts_eur), 2) AS campaign_discounts_eur,
    ROUND(SUM(c.estimated_benefit_costs_eur), 2) AS estimated_reward_and_benefit_costs_eur,
    ROUND(
        SUM(c.gross_subscription_revenue_eur)
        + SUM(c.estimated_transaction_revenue_eur)
        - SUM(c.campaign_discounts_eur)
        - SUM(c.estimated_benefit_costs_eur),
        2
    ) AS estimated_contribution_margin_eur
FROM all_components AS c
JOIN core.plans AS p USING (plan_id)
GROUP BY p.plan_level, p.plan_name, c.acquisition_channel
ORDER BY p.plan_level, c.acquisition_channel;

