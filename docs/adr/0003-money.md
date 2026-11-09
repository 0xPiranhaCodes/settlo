# 0003 Money as integer paise; split and simplification rules

## Status
Accepted (9 Nov 2026)

## Context
Settlo shows balances people compare to the rupee. Floating point drifts (0.1 + 0.2 ≠ 0.3), and rounding a split differently on device and server makes two users see different totals. Splits rarely divide evenly, and debts between n people can produce up to n(n-1)/2 payments.

## Decision
- **Units.** Every amount is integer minor units (paise): `bigint` in Postgres (`*_minor` columns), `int` in Dart. No `double`, no `num`, no decimal strings in models or the database. Conversion to rupees happens only when formatting for display, and parsing user input goes straight to paise.
- **Equal split.** `share = amount ~/ n`, `remainder = amount % n`. The remainder paise go to the payer. When there are several payers, they go to the first payer in member order. Example: ₹100.00 (10000) across 3 → payer 3334, others 3333 each.
- **Integrity.** For every expense, sum(payers) = sum(splits) = amount, enforced by the deferred constraint trigger in Postgres (M1-01) and checked on device before a mutation is queued.
- **Simplification.** Net each member (paid minus owed). Repeatedly match the largest debtor to the largest creditor for min(|debt|, credit) until all nets are zero. This takes at most n-1 payments. It runs on device from the synced balances; the server stores expenses and settlements, not the suggested payments.

## Consequences
- Dart `int` is 64-bit on mobile, so overflow is not a practical risk for INR.
- The money helpers live in `core` (M1-07) and are the only place splits and simplification are computed. QA owns property tests: splits sum to the amount, the remainder goes to the payer, and simplification nets to zero with at most n-1 payments.
- The greedy algorithm is not always the minimum number of payments (that problem is NP-hard), but it is deterministic, fast, and bounded by n-1. If we ever need fewer payments, that change gets a new ADR.
- Percent and shares splits must also use whole paise. Their rounding rule is decided in the issue that implements them, with the remainder going to the payer by default.
