\set ON_ERROR_STOP on

CREATE TEMP VIEW quality_failures AS
WITH sequenced AS (
    SELECT
        se.*,
        LAG(se.new_plan_id) OVER (
            PARTITION BY se.user_id
            ORDER BY se.event_timestamp, se.event_id
        ) AS prior_plan_id
    FROM core.subscription_events AS se
),
invalid_transitions AS (
    SELECT s.event_id, s.user_id, s.event_type
    FROM sequenced AS s
    JOIN core.plans AS old_plan ON old_plan.plan_id = s.old_plan_id
    JOIN core.plans AS new_plan ON new_plan.plan_id = s.new_plan_id
    WHERE
        (s.event_type = 'subscription_started' AND (
            s.prior_plan_id IS NOT NULL OR old_plan.plan_level <> 0 OR new_plan.plan_level = 0
        ))
        OR (s.event_type <> 'subscription_started' AND s.prior_plan_id IS DISTINCT FROM s.old_plan_id)
        OR (s.event_type = 'renewed' AND (
            s.old_plan_id <> s.new_plan_id OR old_plan.plan_level = 0
        ))
        OR (s.event_type = 'upgraded' AND new_plan.plan_level <= old_plan.plan_level)
        OR (s.event_type = 'downgraded' AND (
            new_plan.plan_level >= old_plan.plan_level OR new_plan.plan_level = 0
        ))
        OR (s.event_type = 'cancelled' AND (
            old_plan.plan_level = 0 OR new_plan.plan_level <> 0
        ))
        OR (s.event_type = 'payment_failed' AND (
            s.old_plan_id <> s.new_plan_id OR old_plan.plan_level = 0
        ))
),
duplicate_identifiers AS (
    SELECT 'users.user_id' AS source, user_id::TEXT AS identifier
    FROM core.users GROUP BY user_id HAVING COUNT(*) > 1
    UNION ALL
    SELECT 'subscription_events.event_id', event_id::TEXT
    FROM core.subscription_events GROUP BY event_id HAVING COUNT(*) > 1
    UNION ALL
    SELECT 'transactions.transaction_id', transaction_id::TEXT
    FROM core.transactions GROUP BY transaction_id HAVING COUNT(*) > 1
    UNION ALL
    SELECT 'feature_usage.usage_id', usage_id::TEXT
    FROM core.feature_usage GROUP BY usage_id HAVING COUNT(*) > 1
),
contradictory_histories AS (
    SELECT user_id
    FROM core.subscription_events
    GROUP BY user_id
    HAVING COUNT(*) FILTER (WHERE event_type = 'subscription_started') <> 1
        OR COUNT(*) FILTER (WHERE event_type = 'cancelled') > 1
),
same_time_states AS (
    SELECT user_id, event_timestamp
    FROM core.subscription_events
    WHERE event_type <> 'payment_failed'
    GROUP BY user_id, event_timestamp
    HAVING COUNT(*) > 1
)
SELECT 'duplicate primary business identifiers'::TEXT AS check_name,
       source || ':' || identifier AS record_key, 'identifier is repeated'::TEXT AS details
FROM duplicate_identifiers
UNION ALL
SELECT 'orphan subscription user', se.event_id::TEXT, 'user_id=' || se.user_id
FROM core.subscription_events AS se
LEFT JOIN core.users AS u USING (user_id)
WHERE u.user_id IS NULL
UNION ALL
SELECT 'orphan transaction user', t.transaction_id::TEXT, 'user_id=' || t.user_id
FROM core.transactions AS t
LEFT JOIN core.users AS u USING (user_id)
WHERE u.user_id IS NULL
UNION ALL
SELECT 'orphan feature user', f.usage_id::TEXT, 'user_id=' || f.user_id
FROM core.feature_usage AS f
LEFT JOIN core.users AS u USING (user_id)
WHERE u.user_id IS NULL
UNION ALL
SELECT 'missing required values', user_id::TEXT, 'required user field is null'
FROM core.users
WHERE signup_timestamp IS NULL OR country IS NULL OR acquisition_channel IS NULL OR birth_year IS NULL
UNION ALL
SELECT 'negative transaction amounts', transaction_id::TEXT, amount_original::TEXT
FROM core.transactions
WHERE amount_original <= 0 OR amount_eur <= 0
UNION ALL
SELECT 'unsupported currencies', transaction_id::TEXT, currency::TEXT
FROM core.transactions
WHERE currency NOT IN ('EUR', 'GBP', 'USD', 'PLN', 'RON', 'CHF', 'SEK')
UNION ALL
SELECT 'invalid FX rates', transaction_id::TEXT, fx_rate_to_eur::TEXT
FROM core.transactions
WHERE fx_rate_to_eur <= 0
   OR ABS(amount_eur - ROUND(amount_original * fx_rate_to_eur, 2)) > 0.01
UNION ALL
SELECT 'transactions before signup', t.transaction_id::TEXT, t.transaction_timestamp::TEXT
FROM core.transactions AS t
JOIN core.users AS u USING (user_id)
WHERE t.transaction_timestamp < u.signup_timestamp
UNION ALL
SELECT 'feature usage before signup', f.usage_id::TEXT, f.usage_timestamp::TEXT
FROM core.feature_usage AS f
JOIN core.users AS u USING (user_id)
WHERE f.usage_timestamp < u.signup_timestamp
UNION ALL
SELECT 'subscription events before signup', se.event_id::TEXT, se.event_timestamp::TEXT
FROM core.subscription_events AS se
JOIN core.users AS u USING (user_id)
WHERE se.event_timestamp < u.signup_timestamp
UNION ALL
SELECT 'invalid plan transitions', event_id::TEXT, event_type
FROM invalid_transitions
UNION ALL
SELECT 'cancellations without active paid subscription', event_id::TEXT, event_type
FROM invalid_transitions
WHERE event_type = 'cancelled'
UNION ALL
SELECT 'overlapping contradictory subscription states', user_id::TEXT, 'contradictory lifecycle'
FROM contradictory_histories
UNION ALL
SELECT 'overlapping contradictory subscription states', user_id::TEXT, event_timestamp::TEXT
FROM same_time_states
UNION ALL
SELECT 'impossible campaign dates', campaign_id::TEXT, start_date || ' to ' || end_date
FROM core.marketing_campaigns
WHERE end_date < start_date
UNION ALL
SELECT 'campaign assigned outside active dates', u.user_id::TEXT, u.signup_timestamp::DATE::TEXT
FROM core.users AS u
JOIN core.marketing_campaigns AS c ON c.campaign_id = u.acquisition_campaign_id
WHERE u.signup_timestamp::DATE NOT BETWEEN c.start_date AND c.end_date;

WITH expected_checks(check_name) AS (
    VALUES
        ('duplicate primary business identifiers'),
        ('orphan subscription user'),
        ('orphan transaction user'),
        ('orphan feature user'),
        ('missing required values'),
        ('negative transaction amounts'),
        ('unsupported currencies'),
        ('invalid FX rates'),
        ('transactions before signup'),
        ('feature usage before signup'),
        ('subscription events before signup'),
        ('invalid plan transitions'),
        ('cancellations without active paid subscription'),
        ('overlapping contradictory subscription states'),
        ('impossible campaign dates'),
        ('campaign assigned outside active dates')
)
SELECT e.check_name, COUNT(q.record_key) AS invalid_rows
FROM expected_checks AS e
LEFT JOIN quality_failures AS q USING (check_name)
GROUP BY e.check_name
ORDER BY e.check_name;

DO $$
DECLARE
    failure_count INTEGER;
    failure_sample TEXT;
BEGIN
    SELECT COUNT(*), MIN(check_name || ' [' || record_key || ']')
    INTO failure_count, failure_sample
    FROM quality_failures;

    IF failure_count > 0 THEN
        RAISE EXCEPTION 'Data-quality checks failed: % invalid rows. Example: %',
            failure_count, failure_sample;
    END IF;
END $$;

