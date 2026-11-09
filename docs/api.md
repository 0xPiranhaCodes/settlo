# Settlo API

Owner: Principal Backend. Every amount is integer paise (`bigint`, `*_minor`; ADR 0003).
Clients read and write through PostgREST under the caller's JWT, so row-level security decides
what each caller sees.

## Views

All views are `security_invoker = true`: they read the underlying tables as the caller, so RLS on
`space_members`, `expenses`, `expense_payers`, `expense_splits`, `loans` and `loan_repayments`
applies (policies: #8). `authenticated` can `select`; `anon` cannot. They are read-only.

Common rules:
- A soft-deleted expense (`deleted_at` set) never counts.
- A settlement (`is_settlement`) is a transfer, not spending: it counts toward balances and is
  left out of fairness and categories.
- Months are the first day of the month of `expenses.spent_on`, as a `date`.

### `space_member_balances`
One row per space member (members who left included, so their balance stays visible).

| Column | Type | Meaning |
| --- | --- | --- |
| `space_id`, `member_id` | uuid | Member's space and `space_members.id` |
| `phone`, `user_id` | e164, uuid | Member identity (`user_id` null until they join) |
| `paid_minor` | bigint | Sum of their `expense_payers` rows |
| `owed_minor` | bigint | Sum of their `expense_splits` rows |
| `balance_minor` | bigint | `paid - owed`: positive is owed to them, negative they owe |

Balances in a space sum to zero. Debt simplification runs on device from these rows (ADR 0003).

```
GET /rest/v1/space_member_balances?space_id=eq.<id>
```

### `space_monthly_fairness`
Who paid against their fair share, per member per month (Space and SpacesList canvas). Every
member of the space has a row for every month in which the space has spending, zeros included.

| Column | Type | Meaning |
| --- | --- | --- |
| `space_id`, `month` | uuid, date | Space and month |
| `member_id`, `phone`, `user_id` | | Member |
| `paid_minor` | bigint | What they paid for that month's spending |
| `fair_share_minor` | bigint | Sum of their splits that month (the white tick) |
| `difference_minor` | bigint | `paid - fair share`; positive means they carried more |
| `month_total_minor` | bigint | The space's total spending that month |

Percentages ("you paid 49% of ₹18,450, fair share 33%") are `paid / total` and `fair / total`,
computed on device.

```
GET /rest/v1/space_monthly_fairness?space_id=eq.<id>&month=eq.2026-11-01
```

### `space_monthly_categories`
| Column | Type | Meaning |
| --- | --- | --- |
| `space_id`, `month` | uuid, date | Space and month |
| `category` | text | `expenses.category`; null is its own group |
| `total_minor` | bigint | Spending in that category |
| `expense_count` | int | Number of expenses |

### `loan_summaries`
One row per loan (Loan canvas: ring, three stat tiles, pending repayments). It is
`loan_summaries_as_of` pinned to today's date in India (`Asia/Kolkata`; v1 is INR only).

| Column | Type | Meaning |
| --- | --- | --- |
| `loan_id` … `closed_at` | | Copied from `loans` |
| `repaid_minor` | bigint | Principal of **confirmed** repayments only |
| `outstanding_minor` | bigint | `principal_minor - repaid_minor` |
| `confirmed_count`, `pending_count`, `disputed_count` | int | Repayments by status |
| `pending_minor` | bigint | Amount awaiting the other party's confirmation |
| `installments_total` | int | `ceil(principal / instalment)` |
| `installments_paid` | int | `floor(repaid / instalment)`, or the total once fully repaid |
| `installments_due` | int | Instalments whose due date is before today |
| `expected_minor` | bigint | `min(principal, instalment × installments_due)` |
| `next_due_on` | date | Next instalment date on or after today; null when closed, repaid or past the schedule |
| `ends_on` | date | Date of the last instalment |
| `on_track` | boolean | `repaid_minor >= expected_minor`; null when closed |

Schedule: instalment *k* (1..n) is due on `due_day` of the *k*-th month after the month of
`start_on`. An instalment is not overdue on its due day, only after it. Prepaying keeps a loan on
track; `next_due_on` still shows the next calendar instalment. For `flexible` loans every
schedule column (`installments_*`, `expected_minor`, `next_due_on`, `ends_on`, `on_track`) is null.

```
GET /rest/v1/loan_summaries?loan_id=eq.<id>
```

## Functions

### `loan_summaries_as_of(p_as_of date)`
Returns `loan_summaries` rows computed as of `p_as_of`. Security invoker (RLS applies);
executable by `authenticated` only. Used by tests and for "what was due on" questions.

```
POST /rest/v1/rpc/loan_summaries_as_of  {"p_as_of": "2026-12-05"}
```
