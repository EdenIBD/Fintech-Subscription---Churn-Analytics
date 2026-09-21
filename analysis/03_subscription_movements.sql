\set ON_ERROR_STOP on

SELECT *
FROM analytics.v_monthly_subscription_movements
ORDER BY month_start;
