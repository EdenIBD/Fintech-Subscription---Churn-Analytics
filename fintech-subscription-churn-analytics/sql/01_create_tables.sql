\set ON_ERROR_STOP on

CREATE TABLE core.plans (
    plan_id SMALLINT PRIMARY KEY,
    plan_name TEXT NOT NULL UNIQUE,
    monthly_price_eur NUMERIC(8, 2) NOT NULL CHECK (monthly_price_eur >= 0),
    plan_level SMALLINT NOT NULL UNIQUE CHECK (plan_level BETWEEN 0 AND 4)
);

CREATE TABLE core.marketing_campaigns (
    campaign_id INTEGER PRIMARY KEY,
    campaign_name TEXT NOT NULL UNIQUE,
    start_date DATE NOT NULL,
    end_date DATE NOT NULL,
    discount_months SMALLINT NOT NULL CHECK (discount_months BETWEEN 0 AND 12),
    discount_percentage NUMERIC(5, 2) NOT NULL CHECK (discount_percentage BETWEEN 0 AND 100),
    acquisition_cost_eur NUMERIC(8, 2) NOT NULL CHECK (acquisition_cost_eur >= 0),
    CHECK (end_date >= start_date)
);

CREATE TABLE core.users (
    user_id BIGINT PRIMARY KEY,
    signup_timestamp TIMESTAMP NOT NULL,
    country CHAR(2) NOT NULL,
    acquisition_channel TEXT NOT NULL CHECK (
        acquisition_channel IN ('organic', 'referral', 'paid_social', 'search', 'partner')
    ),
    birth_year SMALLINT NOT NULL CHECK (birth_year BETWEEN 1940 AND 2010),
    verification_timestamp TIMESTAMP,
    first_deposit_timestamp TIMESTAMP,
    acquisition_campaign_id INTEGER REFERENCES core.marketing_campaigns(campaign_id),
    CHECK (verification_timestamp IS NULL OR verification_timestamp >= signup_timestamp),
    CHECK (
        first_deposit_timestamp IS NULL
        OR (
            verification_timestamp IS NOT NULL
            AND first_deposit_timestamp >= verification_timestamp
        )
    )
);

CREATE TABLE core.subscription_events (
    event_id BIGINT PRIMARY KEY,
    user_id BIGINT NOT NULL REFERENCES core.users(user_id),
    event_timestamp TIMESTAMP NOT NULL,
    event_type TEXT NOT NULL CHECK (
        event_type IN (
            'subscription_started', 'renewed', 'upgraded',
            'downgraded', 'cancelled', 'payment_failed'
        )
    ),
    old_plan_id SMALLINT NOT NULL REFERENCES core.plans(plan_id),
    new_plan_id SMALLINT NOT NULL REFERENCES core.plans(plan_id),
    event_reason TEXT NOT NULL,
    campaign_id INTEGER REFERENCES core.marketing_campaigns(campaign_id)
);

CREATE TABLE core.transactions (
    transaction_id BIGINT PRIMARY KEY,
    user_id BIGINT NOT NULL REFERENCES core.users(user_id),
    transaction_timestamp TIMESTAMP NOT NULL,
    transaction_type TEXT NOT NULL CHECK (
        transaction_type IN (
            'card_purchase', 'international_transfer', 'cash_withdrawal',
            'fx_exchange', 'card_to_card_transfer'
        )
    ),
    status TEXT NOT NULL CHECK (status IN ('successful', 'failed')),
    amount_original NUMERIC(14, 2) NOT NULL CHECK (amount_original > 0),
    currency CHAR(3) NOT NULL CHECK (currency IN ('EUR', 'GBP', 'USD', 'PLN', 'RON', 'CHF', 'SEK')),
    fx_rate_to_eur NUMERIC(12, 6) NOT NULL CHECK (fx_rate_to_eur > 0),
    amount_eur NUMERIC(14, 2) NOT NULL CHECK (amount_eur > 0)
);

CREATE TABLE core.feature_usage (
    usage_id BIGINT PRIMARY KEY,
    user_id BIGINT NOT NULL REFERENCES core.users(user_id),
    feature_name TEXT NOT NULL CHECK (
        feature_name IN (
            'budgeting', 'card_payments', 'international_transfers',
            'airport_lounge', 'savings', 'rewards'
        )
    ),
    usage_timestamp TIMESTAMP NOT NULL
);
