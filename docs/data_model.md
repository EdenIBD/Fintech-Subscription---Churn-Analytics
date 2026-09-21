# Data model

NovaPay is fictional. All records and commercial assumptions are synthetic.

## Tables

| Table | Grain | Purpose |
|---|---|---|
| `core.users` | One row per user | Signup, onboarding milestones, geography, acquisition source, and optional campaign attribution |
| `core.plans` | One row per plan | Five plan levels and their list prices |
| `core.subscription_events` | One row per subscription event | Ordered changes to a user's paid-plan state |
| `core.transactions` | One row per transaction attempt | Successful and failed activity, original currency, synthetic FX rate, and EUR value |
| `core.feature_usage` | One row per feature use | Product and paid-benefit engagement |
| `core.marketing_campaigns` | One row per campaign | Active dates, discount terms, and assumed per-user acquisition cost |

Primary keys identify rows uniquely. Foreign keys prevent references to users, plans, or campaigns that do not exist. `NOT NULL`, `UNIQUE`, and `CHECK` constraints reject many invalid values before analysis.

## Subscription state

Subscription history is event-based because a user can change plans several times. Sort `subscription_events` by `user_id`, `event_timestamp`, and `event_id`; each event's `new_plan_id` becomes the state until the next state-changing event. A payment failure records an attempt but does not itself change the plan. Cancellation moves a paid user to Basic.

`analytics.v_subscription_timeline` uses `LEAD` to turn events into `[valid_from, valid_to)` intervals. `analytics.v_paid_lifecycle` provides one paid start and optional churn timestamp per paid user. The generator intentionally creates no re-subscriptions, which keeps the model approachable.

## Currency conversion

`amount_original` must never be summed across currencies. `amount_eur` is the comparable value and equals `amount_original * fx_rate_to_eur`, rounded to cents. The generator uses fixed illustrative rates for EUR, GBP, USD, PLN, RON, CHF, and SEK. It does not model intraday rates, fees, spreads, or rate history.

## Synthetic relationships

The fixed-seed generator makes declining activity, low benefit engagement, large campaign discounts, and payment problems increase churn probability. The relationships remain probabilistic. They are test data assumptions, not findings about any real company or customer population.

