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

## RPCs (#10)

Called as `POST /rest/v1/rpc/<name>` with the caller's JWT. Executable by `authenticated` only;
`anon` and `public` cannot call them. The caller's phone must be verified (`phone_confirmed_at`),
otherwise every RPC fails with `42501`. Errors come back as PostgREST errors carrying the
Postgres `code`:

| Code | Meaning |
| --- | --- |
| `22023` | Invalid payload (missing field, sums do not match, member not active in the space) |
| `22P02`, `23514` | A value of the wrong type, e.g. a non-uuid id or a phone that is not E.164 |
| `42501` | Not allowed: unverified caller, not an active member, soft-deleted space, another user's space id |
| `PT409` | HTTP 409, hint `idempotency_conflict`: the key was already used with a different payload (or by another member) |
| `PT429` | HTTP 429, hint `lookup_quota_exceeded`: `lookup_phones` daily quota used up |
| `54000` | `lookup_phones` batch over 500 hashes |

Per ADR 0004, a rejection means the queued mutation is dropped and its optimistic change rolled
back; a network error means retry with the same key. `PT409` is a conflict, not a plain rejection:
the server holds a different mutation under that key, so the queue surfaces it to the user for
reconciliation instead of treating the replay as done.

Idempotency is payload-bound: the server stores a SHA-256 fingerprint of the normalised request with
the key. Same key and same payload returns the original id and writes nothing; same key and a
different payload is `PT409`. This holds for concurrent calls too: the second waits for the first to
commit, then compares.

### `create_space(p_name, p_kind, p_members, p_idempotency_key)`
Creates the space, the caller as its `owner`, and one `member` row per entry in `p_members`, in a
single transaction. Security invoker: RLS on `spaces` and `space_members` applies.

| Parameter | Type | Meaning |
| --- | --- | --- |
| `p_name` | text | Required, non-blank |
| `p_kind` | `space_kind` | `flat`, `trip`, `friend` or `other` |
| `p_members` | jsonb | `[{"phone": "+91…", "name": "…"}]`, default `[]`. Phones must be E.164 and distinct. The caller's own phone is skipped. `name` is the creator's label for that member, stored on `space_members.name`. |
| `p_idempotency_key` | uuid | Optional. Becomes the space id, so the client knows it offline and can queue expenses against it. A replay by the creator with the same payload (name trimmed, kind, members in any order) returns the same id and writes nothing; a different payload is `PT409`. Someone else's space id fails with `42501`. |

```
POST /rest/v1/rpc/create_space
{
  "p_name": "Flat 7C",
  "p_kind": "flat",
  "p_members": [{"phone": "+919100000002", "name": "Bilal"}, {"phone": "+919800000009", "name": "Xavier"}],
  "p_idempotency_key": "6f1c2e3a-8d4b-4f6e-9a1b-2c3d4e5f6a7b"
}

200 "6f1c2e3a-8d4b-4f6e-9a1b-2c3d4e5f6a7b"
```

### `add_expense(p jsonb)`
Validates and inserts the expense, its payers and its splits in one transaction, and returns the
expense id. Security invoker: RLS applies, and the caller becomes `created_by`.

| Field | Type | Meaning |
| --- | --- | --- |
| `idempotency_key` | uuid | Required. Generated once on device (ADR 0004) |
| `space_id` | uuid | Required. The caller must be an active member of a live space |
| `description` | text | Required, non-blank |
| `category` | text | Optional |
| `amount_minor` | integer | Required, > 0, paise |
| `spent_on` | date | Optional, default today (UTC) |
| `is_settlement` | boolean | Optional, default `false` |
| `split_type` | text | `equal` (default), `exact`, `percent` or `shares` |
| `payers` | array | `[{"member_id", "amount_minor"}]`: distinct active members, amounts > 0, summing to `amount_minor` |
| `splits` | array | `[{"member_id", "amount_minor", "percent_bp", "shares"}]`: distinct active members |

Splits:
- `equal`: the server recomputes the amounts and ignores any sent: each split member gets
  `amount / n` and the remainder goes to the first split member (in array order) who is also a
  payer, else the first split member. This matches `splitEqual` in `packages/core` (ADR 0003).
- `exact`: the client's amounts must be non-negative and sum to `amount_minor` (`splitExact`).
- `percent`, `shares`: `percent` needs `percent_bp` on every split, summing to 10000; `shares` needs
  a positive `shares` on every split. The server recomputes the allocation with the same rule as
  `splitPercent` / `splitShares` and rejects (`22023`) any client amount that differs: each member
  gets `floor(amount × w / total)`, and the leftover paise go one each to the largest discarded
  fractions, ties to the payer (as above) first, then split order. So amounts that sum correctly but
  contradict the weights (50/50 with 9000/1000 bp) are rejected.

Idempotency (see above): the fingerprint covers every stored field plus payers (any order) and
splits (in order, since order decides the remainder). Client amounts on `equal` splits are ignored
by the server and so are not part of it. `spent_on` counts as sent, so omitting it on the first call
and on replays matches even across midnight.

```
POST /rest/v1/rpc/add_expense
{
  "p": {
    "idempotency_key": "0b9d7c1e-2f3a-4b5c-8d6e-7f8a9b0c1d2e",
    "space_id": "6f1c2e3a-8d4b-4f6e-9a1b-2c3d4e5f6a7b",
    "description": "Groceries",
    "category": "food",
    "amount_minor": 10000,
    "spent_on": "2026-11-09",
    "split_type": "equal",
    "payers": [{"member_id": "<Bilal>", "amount_minor": 10000}],
    "splits": [{"member_id": "<Asha>"}, {"member_id": "<Bilal>"}, {"member_id": "<Xavier>"}]
  }
}

200 "c4a1e7f2-5b6d-4e8f-9a0b-1c2d3e4f5a6b"
```
Stored splits: Asha 3333, Bilal 3334 (payer, takes the remainder), Xavier 3333. Replaying the same
body returns `"c4a1e7f2-…"` again.

```
{"p": {…, "split_type": "exact", "amount_minor": 1000,
       "splits": [{"member_id": "<Asha>", "amount_minor": 500}, {"member_id": "<Bilal>", "amount_minor": 400}]}}

400 {"code": "22023", "message": "add_expense: split amounts must be non-negative and sum to 1000", …}
```

### `lookup_phones(p_hashes text[])`
Contact discovery without sending raw numbers. The client hashes each contact's E.164 number on
device as lowercase hex SHA-256 of its UTF-8 bytes (`'+919100000002'` →
`sha256("+919100000002")`, the same as `public.phone_hash`) and sends the hashes. It returns one
row per hash that belongs to a registered user with a verified phone; unknown and unverified numbers
return nothing. The phone number is never returned. Security definer (it must match profiles the
caller cannot otherwise read) with a fixed `search_path`.

- At most 500 hashes per call (`54000` otherwise); the client batches. Every entry must be 64 hex
  characters (`22023`), so a raw number is rejected. Uppercase hex is accepted; results are lowercase.
- Quota: a hash only hides a number from casual view (Indian mobile numbers are a small space to
  enumerate), so every hash sent, matched or not, is charged to a per-user daily budget before the
  lookup: 1000 hashes per verified user per day (Asia/Kolkata). A call that would go over fails with
  `PT429` (HTTP 429, hint `lookup_quota_exceeded`) and is not charged; the client should stop and try
  the remaining contacts the next day. The budget lives in `private.lookup_quota`, outside the
  PostgREST schemas with no client privileges, so it cannot be read, reset or bypassed. Change the
  limit with `update private.settings set value = '<n>' where key = 'lookup_phones_daily_hashes'`.
  There is no burst limit beyond the 500-per-call cap.
- A profile matches only while its phone is still the user's verified auth phone.

```
POST /rest/v1/rpc/lookup_phones
{"p_hashes": [
  "<sha256 of +919100000002>",
  "<sha256 of +919800000009>"
]}

200 [{"phone_hash": "<sha256 of +919100000002>", "user_id": "00000000-…-00000000a002", "name": "Bilal"}]
```
