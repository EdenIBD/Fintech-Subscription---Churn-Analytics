\set ON_ERROR_STOP on

CREATE INDEX idx_subscription_events_user_time
    ON core.subscription_events (user_id, event_timestamp DESC)
    INCLUDE (event_type, old_plan_id, new_plan_id, event_reason);

CREATE INDEX idx_transactions_user_time
    ON core.transactions (user_id, transaction_timestamp)
    INCLUDE (status, amount_eur, transaction_type);

CREATE INDEX idx_feature_usage_user_time
    ON core.feature_usage (user_id, usage_timestamp)
    INCLUDE (feature_name);

ANALYZE core.subscription_events;
ANALYZE core.transactions;
ANALYZE core.feature_usage;
