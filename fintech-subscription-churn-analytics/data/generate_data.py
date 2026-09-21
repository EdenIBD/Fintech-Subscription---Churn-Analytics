#!/usr/bin/env python3
"""Generate a reproducible synthetic dataset for the NovaPay SQL project."""

import argparse
import csv
import math
import random
from datetime import date, datetime, timedelta
from pathlib import Path


SEED = 20270101
USER_COUNT = 15_000
CUTOFF = datetime(2025, 12, 31, 23, 59, 59)
SIGNUP_START = datetime(2023, 1, 1)
SIGNUP_END = datetime(2025, 9, 30, 23, 59, 59)

PLANS = [
    (1, "Basic", "0.00", 0),
    (2, "Plus", "4.99", 1),
    (3, "Premium", "9.99", 2),
    (4, "Metal", "16.99", 3),
    (5, "Elite", "29.99", 4),
]
PLAN_PRICE = {row[0]: float(row[2]) for row in PLANS}
PLAN_LEVEL = {row[0]: row[3] for row in PLANS}

CAMPAIGNS = [
    (1, "Spring Starter", date(2023, 1, 1), date(2023, 6, 30), 3, 50, "35.00"),
    (2, "Summer Abroad", date(2023, 7, 1), date(2023, 12, 31), 2, 30, "42.00"),
    (3, "Premium Trial", date(2024, 1, 1), date(2024, 6, 30), 3, 70, "48.00"),
    (4, "Everyday Banking", date(2024, 7, 1), date(2024, 12, 31), 2, 20, "30.00"),
    (5, "Metal Explorer", date(2025, 1, 1), date(2025, 6, 30), 4, 40, "65.00"),
    (6, "Referral Rewards", date(2025, 7, 1), date(2025, 9, 30), 1, 15, "25.00"),
]
CAMPAIGN_BY_ID = {row[0]: row for row in CAMPAIGNS}

FX_RATES = {
    "EUR": 1.0,
    "GBP": 1.17,
    "USD": 0.92,
    "PLN": 0.23,
    "RON": 0.20,
    "CHF": 1.04,
    "SEK": 0.088,
}


def random_datetime(rng, start, end):
    if end <= start:
        return start
    return start + timedelta(seconds=rng.randint(0, int((end - start).total_seconds())))


def month_distance(start, end):
    return max(0, (end.year - start.year) * 12 + end.month - start.month)


def iso(value):
    return value.isoformat(sep=" ", timespec="seconds") if isinstance(value, datetime) else value


def write_csv(path, header, rows):
    with path.open("w", newline="", encoding="utf-8") as handle:
        writer = csv.writer(handle)
        writer.writerow(header)
        writer.writerows([["" if value is None else iso(value) for value in row] for row in rows])


def weighted_choice(rng, choices):
    values, weights = zip(*choices)
    return rng.choices(values, weights=weights, k=1)[0]


def generate(output_dir):
    rng = random.Random(SEED)
    output_dir.mkdir(parents=True, exist_ok=True)

    countries = [("GB", 22), ("DE", 18), ("FR", 15), ("ES", 12), ("IT", 11),
                 ("NL", 8), ("PL", 8), ("RO", 6)]
    channels = [("organic", 34), ("referral", 24), ("paid_social", 18),
                ("search", 15), ("partner", 9)]

    users = []
    user_meta = {}
    subscription_events = []
    next_event_id = 1

    for user_id in range(1, USER_COUNT + 1):
        signup = random_datetime(rng, SIGNUP_START, SIGNUP_END)
        country = weighted_choice(rng, countries)
        channel = weighted_choice(rng, channels)
        birth_year = rng.randint(1955, 2005)

        eligible_campaign = next(c for c in CAMPAIGNS if c[2] <= signup.date() <= c[3])
        campaign_probability = 0.58 if channel in {"paid_social", "partner"} else 0.30
        campaign_id = eligible_campaign[0] if rng.random() < campaign_probability else None

        verification = None
        if rng.random() < 0.925:
            candidate = signup + timedelta(hours=rng.randint(1, 168))
            verification = candidate if candidate <= CUTOFF else None

        first_deposit = None
        if verification and rng.random() < 0.895:
            candidate = verification + timedelta(hours=rng.randint(1, 240))
            first_deposit = candidate if candidate <= CUTOFF else None

        first_transaction = None
        if first_deposit and rng.random() < 0.965:
            candidate = first_deposit + timedelta(hours=rng.randint(1, 168))
            first_transaction = candidate if candidate <= CUTOFF else None

        activity_score = rng.randint(1, 6)
        declining = rng.random() < 0.30
        benefit_engagement = rng.random()
        failure_prone = rng.random() < 0.16

        users.append((
            user_id, signup, country, channel, birth_year, verification,
            first_deposit, campaign_id,
        ))

        paid_start = None
        churn_timestamp = None
        involuntary = False
        current_plan = 1

        paid_probability = 0.20 + activity_score * 0.025
        if campaign_id:
            paid_probability += 0.10 + CAMPAIGN_BY_ID[campaign_id][5] / 500.0
        if channel == "referral":
            paid_probability += 0.035

        if first_transaction and rng.random() < min(0.72, paid_probability):
            candidate = first_transaction + timedelta(days=rng.randint(2, 45))
            if candidate <= CUTOFF:
                paid_start = candidate
                current_plan = weighted_choice(
                    rng, [(2, 43), (3, 34), (4, 17), (5, 6)]
                )
                reason = "campaign_offer" if campaign_id else "standard_signup"
                subscription_events.append((
                    next_event_id, user_id, paid_start, "subscription_started",
                    1, current_plan, reason, campaign_id,
                ))
                next_event_id += 1

                due = paid_start + timedelta(days=30)
                while due <= CUTOFF:
                    failure = rng.random() < (0.035 + 0.075 * failure_prone)
                    if failure:
                        subscription_events.append((
                            next_event_id, user_id, due, "payment_failed",
                            current_plan, current_plan, "payment_method_failed", None,
                        ))
                        next_event_id += 1
                        if rng.random() < (0.43 + 0.22 * failure_prone):
                            cancel_time = due + timedelta(days=2)
                            if cancel_time <= CUTOFF:
                                subscription_events.append((
                                    next_event_id, user_id, cancel_time, "cancelled",
                                    current_plan, 1, "payment_failure", None,
                                ))
                                next_event_id += 1
                                churn_timestamp = cancel_time
                                involuntary = True
                                current_plan = 1
                                break

                    churn_probability = 0.075
                    churn_probability += 0.075 if declining else 0
                    churn_probability += 0.04 if failure_prone else 0
                    churn_probability -= 0.05 if benefit_engagement > 0.65 else 0
                    if campaign_id and CAMPAIGN_BY_ID[campaign_id][5] >= 40:
                        churn_probability += 0.035
                    churn_probability = max(0.025, min(0.24, churn_probability))

                    event_time = due + timedelta(days=2) if failure else due
                    if event_time > CUTOFF:
                        break
                    if rng.random() < churn_probability:
                        subscription_events.append((
                            next_event_id, user_id, event_time, "cancelled",
                            current_plan, 1, "customer_choice", None,
                        ))
                        next_event_id += 1
                        churn_timestamp = event_time
                        current_plan = 1
                        break

                    old_plan = current_plan
                    movement = rng.random()
                    if movement < 0.035 and current_plan < 5:
                        current_plan += 1
                        event_type = "upgraded"
                        event_reason = "more_features"
                    elif movement < 0.065 and current_plan > 2:
                        current_plan -= 1
                        event_type = "downgraded"
                        event_reason = "lower_cost"
                    else:
                        event_type = "renewed"
                        event_reason = "scheduled_renewal"
                    subscription_events.append((
                        next_event_id, user_id, event_time, event_type,
                        old_plan, current_plan, event_reason, None,
                    ))
                    next_event_id += 1
                    due += timedelta(days=30)

        user_meta[user_id] = {
            "signup": signup,
            "first_transaction": first_transaction,
            "activity_score": activity_score,
            "declining": declining,
            "benefit_engagement": benefit_engagement,
            "failure_prone": failure_prone,
            "paid_start": paid_start,
            "churn_timestamp": churn_timestamp,
            "involuntary": involuntary,
        }

    transactions = []
    next_transaction_id = 1
    currencies = [("EUR", 58), ("GBP", 11), ("USD", 10), ("PLN", 8),
                  ("RON", 6), ("CHF", 4), ("SEK", 3)]
    transaction_types = [
        ("card_purchase", 68), ("international_transfer", 10),
        ("cash_withdrawal", 9), ("fx_exchange", 8),
        ("card_to_card_transfer", 5),
    ]

    for user_id, meta in user_meta.items():
        first_tx = meta["first_transaction"]
        if not first_tx:
            continue

        def add_transaction(timestamp, transaction_type, status, force_currency=None):
            nonlocal next_transaction_id
            currency = force_currency or weighted_choice(rng, currencies)
            if transaction_type == "card_purchase":
                amount_eur_base = rng.uniform(3, 240)
            elif transaction_type == "cash_withdrawal":
                amount_eur_base = rng.uniform(20, 300)
            else:
                amount_eur_base = rng.uniform(15, 900)
            rate = FX_RATES[currency]
            original = round(amount_eur_base / rate, 2)
            amount_eur = round(original * rate, 2)
            transactions.append((
                next_transaction_id, user_id, timestamp, transaction_type, status,
                f"{original:.2f}", currency, f"{rate:.6f}", f"{amount_eur:.2f}",
            ))
            next_transaction_id += 1

        add_transaction(first_tx, "card_purchase", "successful", "EUR")
        activity_end = meta["churn_timestamp"] or CUTOFF
        months_observed = month_distance(first_tx, activity_end)
        extra_count = (
            5 + int(meta["activity_score"] * 1.35)
            + min(10, months_observed // 3) + rng.randint(0, 4)
        )
        if meta["declining"]:
            extra_count = max(4, int(extra_count * 0.82))

        for _ in range(extra_count):
            churn_ts = meta["churn_timestamp"]
            if churn_ts and rng.random() < 0.88:
                end = max(first_tx, churn_ts - timedelta(minutes=1))
                fraction = rng.random() ** (2.50 if meta["declining"] else 1.40)
                timestamp = first_tx + (end - first_tx) * fraction
            elif churn_ts:
                start = min(CUTOFF, churn_ts + timedelta(minutes=1))
                timestamp = random_datetime(rng, start, CUTOFF)
            else:
                fraction = rng.random() ** (1.30 if meta["declining"] else 0.65)
                timestamp = first_tx + (CUTOFF - first_tx) * fraction

            transaction_type = weighted_choice(rng, transaction_types)
            failure_rate = 0.035 + (0.08 if meta["failure_prone"] else 0)
            status = "failed" if rng.random() < failure_rate else "successful"
            add_transaction(timestamp, transaction_type, status)

        if meta["involuntary"] and meta["churn_timestamp"]:
            for days_before in (47, 18, 4):
                timestamp = meta["churn_timestamp"] - timedelta(days=days_before, hours=rng.randint(0, 20))
                if timestamp >= first_tx:
                    add_transaction(timestamp, "card_purchase", "failed", "EUR")

    feature_usage = []
    next_usage_id = 1
    basic_features = ["budgeting", "card_payments", "savings"]
    paid_features = ["rewards", "international_transfers", "airport_lounge"]

    for user_id, meta in user_meta.items():
        first_tx = meta["first_transaction"]
        if not first_tx:
            continue
        for _ in range(rng.randint(2, 6)):
            timestamp = random_datetime(rng, first_tx, CUTOFF)
            feature_usage.append((
                next_usage_id, user_id, rng.choice(basic_features), timestamp,
            ))
            next_usage_id += 1

        paid_start = meta["paid_start"]
        if paid_start:
            paid_end = meta["churn_timestamp"] or CUTOFF
            usage_count = 2 + int(meta["benefit_engagement"] * 11)
            for _ in range(usage_count):
                timestamp = random_datetime(rng, paid_start, paid_end)
                if meta["benefit_engagement"] > 0.60:
                    feature = rng.choice(paid_features)
                else:
                    feature = rng.choice(basic_features + paid_features[:2])
                feature_usage.append((next_usage_id, user_id, feature, timestamp))
                next_usage_id += 1

    subscription_events.sort(key=lambda row: (row[1], row[2], row[0]))
    transactions.sort(key=lambda row: row[0])

    assert all((u[5] is None or u[5] >= u[1]) and (u[6] is None or u[6] >= u[5]) for u in users)
    assert 30_000 <= len(subscription_events) <= 50_000, len(subscription_events)
    assert 150_000 <= len(transactions) <= 250_000, len(transactions)
    assert all(t[2] >= user_meta[t[1]]["signup"] for t in transactions)

    write_csv(output_dir / "plans.csv",
              ["plan_id", "plan_name", "monthly_price_eur", "plan_level"], PLANS)
    write_csv(output_dir / "marketing_campaigns.csv",
              ["campaign_id", "campaign_name", "start_date", "end_date",
               "discount_months", "discount_percentage", "acquisition_cost_eur"], CAMPAIGNS)
    write_csv(output_dir / "users.csv",
              ["user_id", "signup_timestamp", "country", "acquisition_channel",
               "birth_year", "verification_timestamp", "first_deposit_timestamp",
               "acquisition_campaign_id"], users)
    write_csv(output_dir / "subscription_events.csv",
              ["event_id", "user_id", "event_timestamp", "event_type", "old_plan_id",
               "new_plan_id", "event_reason", "campaign_id"], subscription_events)
    write_csv(output_dir / "transactions.csv",
              ["transaction_id", "user_id", "transaction_timestamp", "transaction_type",
               "status", "amount_original", "currency", "fx_rate_to_eur", "amount_eur"],
              transactions)
    write_csv(output_dir / "feature_usage.csv",
              ["usage_id", "user_id", "feature_name", "usage_timestamp"], feature_usage)

    counts = {
        "users": len(users),
        "plans": len(PLANS),
        "marketing_campaigns": len(CAMPAIGNS),
        "subscription_events": len(subscription_events),
        "transactions": len(transactions),
        "feature_usage": len(feature_usage),
    }
    print(f"Generated with seed {SEED} in {output_dir}")
    for name, count in counts.items():
        print(f"{name}: {count:,}")


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument(
        "--output",
        type=Path,
        default=Path(__file__).resolve().parent / "generated",
    )
    args = parser.parse_args()
    generate(args.output)


if __name__ == "__main__":
    main()
