# Metric definitions

The analysis cutoff is `2025-12-31 23:59:59`. All money is EUR after synthetic FX conversion.

| Metric | Definition |
|---|---|
| Signup | A row in `core.users` |
| Verified user | `verification_timestamp` exists and is on or after signup |
| First depositor | `first_deposit_timestamp` exists after verification |
| First successful transaction | Earliest successful transaction on or after first deposit |
| First paid subscription | Earliest paid `subscription_started` event after the first successful transaction |
| Monthly active user | Distinct user with a transaction attempt or feature-use event during the month |
| Active paid subscriber | Distinct user on Plus, Premium, Metal, or Elite immediately before the next month begins |
| New paid subscriber | User whose first paid start occurs in the month |
| Monthly subscription revenue | Sum of synthetic subscription charges after campaign discounts; failed payments and cancellations create no charge |
| ARPPU | Monthly net subscription revenue divided by active paid subscribers at month end |
| Transaction success rate | Successful attempts divided by all transaction attempts in the month |
| Successful transaction volume | Sum of `amount_eur` for successful transactions |
| Voluntary cancellation | Cancellation with `event_reason = 'customer_choice'` |
| Involuntary churn | Cancellation with `event_reason = 'payment_failure'`, following a failed subscription payment |
| Paid churn rate | Paid cancellations during the month divided by paid subscribers active at the start of that month; inactive Basic users are excluded |
| Paid cohort | Users grouped by the month of first paid subscription |
| Month-N retention | Share of the original cohort still paid at the exact N-month anniversary of its paid start |
| Campaign 3-month retention | Month-3 retention among paid campaign users whose 3-month anniversary is on or before the cutoff |

## Economics assumptions

Plan economics are illustrative, not actual fintech unit economics.

- Transaction revenue rates range from 0.05% to 0.45% of successful EUR volume by transaction type.
- Monthly fixed benefit costs per charged paid month are €0.75 (Plus), €2.50 (Premium), €6.50 (Metal), and €10.50 (Elite).
- Card reward cost is 0.3% for Premium and 0.6% for Metal/Elite.
- Per-use costs are €18.00 for airport lounge, €0.35 for rewards, €0.20 for international transfers, and €0.05 for savings.
- Campaign acquisition cost is the campaign's assumed per-acquired-user cost multiplied by acquired users.

Plan contribution is:

```text
gross subscription revenue
+ estimated transaction revenue
- campaign discounts
- estimated reward and benefit costs
= estimated contribution margin
```

Campaign contribution uses net subscription revenue and additionally subtracts acquisition cost.

