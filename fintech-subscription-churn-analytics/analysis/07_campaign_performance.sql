\set ON_ERROR_STOP on

WITH campaign_users AS (
    SELECT
        c.campaign_id,
        c.campaign_name,
        c.acquisition_cost_eur,
        j.user_id,
        j.verification_timestamp,
        j.first_paid_subscription
    FROM core.marketing_campaigns AS c
    JOIN analytics.v_user_journey AS j
      ON j.acquisition_campaign_id = c.campaign_id
),
funnel AS (
    SELECT
        campaign_id,
        campaign_name,
        acquisition_cost_eur,
        COUNT(*) AS users_acquired,
        COUNT(verification_timestamp) AS verified_users,
        COUNT(first_paid_subscription) AS paid_users
    FROM campaign_users
    GROUP BY campaign_id, campaign_name, acquisition_cost_eur
),
retention AS (
    SELECT
        cu.campaign_id,
        COUNT(*) FILTER (
            WHERE l.paid_start_timestamp + INTERVAL '3 months' <= TIMESTAMP '2025-12-31 23:59:59'
        ) AS mature_paid_users,
        COUNT(*) FILTER (
            WHERE l.paid_start_timestamp + INTERVAL '3 months' <= TIMESTAMP '2025-12-31 23:59:59'
              AND (l.churn_timestamp IS NULL OR l.churn_timestamp > l.paid_start_timestamp + INTERVAL '3 months')
        ) AS retained_at_3_months
    FROM campaign_users AS cu
    JOIN analytics.v_paid_lifecycle AS l USING (user_id)
    GROUP BY cu.campaign_id
),
subscription_value AS (
    SELECT
        cu.campaign_id,
        SUM(sc.net_subscription_revenue_eur) AS subscription_revenue_eur,
        SUM(CASE sc.plan_id WHEN 2 THEN 0.75 WHEN 3 THEN 2.50 WHEN 4 THEN 6.50 WHEN 5 THEN 10.50 ELSE 0 END)
            AS fixed_benefit_cost_eur
    FROM campaign_users AS cu
    JOIN analytics.v_subscription_charges AS sc USING (user_id)
    GROUP BY cu.campaign_id
),
transaction_value AS (
    SELECT
        cu.campaign_id,
        SUM(CASE t.transaction_type
            WHEN 'card_purchase' THEN t.amount_eur * 0.0020
            WHEN 'international_transfer' THEN t.amount_eur * 0.0045
            WHEN 'fx_exchange' THEN t.amount_eur * 0.0015
            WHEN 'cash_withdrawal' THEN t.amount_eur * 0.0010
            ELSE t.amount_eur * 0.0005
        END) AS estimated_transaction_revenue_eur
    FROM campaign_users AS cu
    JOIN core.transactions AS t USING (user_id)
    WHERE t.status = 'successful'
    GROUP BY cu.campaign_id
),
usage_cost AS (
    SELECT
        cu.campaign_id,
        SUM(CASE f.feature_name
            WHEN 'airport_lounge' THEN 18.00
            WHEN 'rewards' THEN 0.35
            WHEN 'international_transfers' THEN 0.20
            WHEN 'savings' THEN 0.05
            ELSE 0
        END) AS variable_benefit_cost_eur
    FROM campaign_users AS cu
    JOIN core.feature_usage AS f USING (user_id)
    GROUP BY cu.campaign_id
)
SELECT
    f.campaign_name,
    f.users_acquired,
    ROUND(100.0 * f.verified_users / f.users_acquired, 2) AS verification_rate_pct,
    ROUND(100.0 * f.paid_users / f.users_acquired, 2) AS paid_conversion_rate_pct,
    CASE WHEN r.mature_paid_users > 0
        THEN ROUND(100.0 * r.retained_at_3_months / r.mature_paid_users, 2)
    END AS three_month_retention_rate_pct,
    COALESCE(r.mature_paid_users, 0) AS mature_paid_users,
    ROUND(COALESCE(s.subscription_revenue_eur, 0), 2) AS subscription_revenue_eur,
    ROUND(f.users_acquired * f.acquisition_cost_eur, 2) AS acquisition_cost_eur,
    ROUND(
        COALESCE(s.subscription_revenue_eur, 0)
        + COALESCE(t.estimated_transaction_revenue_eur, 0)
        - COALESCE(s.fixed_benefit_cost_eur, 0)
        - COALESCE(u.variable_benefit_cost_eur, 0)
        - f.users_acquired * f.acquisition_cost_eur,
        2
    ) AS estimated_contribution_after_acquisition_eur
FROM funnel AS f
LEFT JOIN retention AS r USING (campaign_id)
LEFT JOIN subscription_value AS s USING (campaign_id)
LEFT JOIN transaction_value AS t USING (campaign_id)
LEFT JOIN usage_cost AS u USING (campaign_id)
ORDER BY f.campaign_id;
