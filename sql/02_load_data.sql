\set ON_ERROR_STOP on

COPY core.plans
FROM '/data/generated/plans.csv'
WITH (FORMAT csv, HEADER true);

COPY core.marketing_campaigns
FROM '/data/generated/marketing_campaigns.csv'
WITH (FORMAT csv, HEADER true);

COPY core.users
FROM '/data/generated/users.csv'
WITH (FORMAT csv, HEADER true, NULL '');

COPY core.subscription_events
FROM '/data/generated/subscription_events.csv'
WITH (FORMAT csv, HEADER true, NULL '');

COPY core.transactions
FROM '/data/generated/transactions.csv'
WITH (FORMAT csv, HEADER true);

COPY core.feature_usage
FROM '/data/generated/feature_usage.csv'
WITH (FORMAT csv, HEADER true);

ANALYZE core.plans;
ANALYZE core.marketing_campaigns;
ANALYZE core.users;
ANALYZE core.subscription_events;
ANALYZE core.transactions;
ANALYZE core.feature_usage;

