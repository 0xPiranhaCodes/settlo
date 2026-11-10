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
- A settlement (`is_settlement`) is a transfer, not spending: it counts toward balances only once
  the payee has confirmed it (#78), and is always left out of fairness and categories.
- Months are the first day of the month of `expenses.spent_on`, as a `date`.

### `space_member_balances`
One row per space member (members who left included, so their balance stays visible).

| Column | Type | Meaning |
| --- | --- | --- |
| `space_id`, `member_id` | uuid | Member's space and `space_members.id` |
| `phone`, `user_id` | e164, uuid | Member identity (`user_id` null until they join) |
| `paid_minor` | bigint | Sum of their `expense_payers` rows (pending and disputed settle-ups excluded) |
| `owed_minor` | bigint | Sum of their `expense_splits` rows (likewise) |
| `balance_minor` | bigint | `paid - owed`: positive is owed to them, negative they owe |

Balances in a space sum to zero. Debt simplification runs on device from these rows (ADR 0003).

```
GET /rest/v1/space_member_balances?space_id=eq.<id>
```

### `pending_settlements`
Settle-ups waiting for their payee (#78), one row each, in the spaces the caller can read. Space
lists them as pending; Activity's 'Needs you' (#91) lists the rows with `awaiting_me`.

| Column | Type | Meaning |
| --- | --- | --- |
| `expense_id`, `space_id` | uuid | The settle-up (an `expenses` row) and its space |
| `amount_minor`, `spent_on` | bigint, date | What was paid, and when |
| `created_by`, `created_at` | uuid, timestamptz | Who recorded it, and when |
| `payer_member_id`, `payee_member_id` | uuid | `space_members.id` of who paid and who was paid |
| `awaiting_me` | boolean | The caller is the payee and may answer (an accepted, active member) |

```
GET /rest/v1/pending_settlements?awaiting_me=is.true&order=created_at.desc
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

### `activity_feed(p_before_at timestamptz, p_before_id bigint, p_limit int, p_space_id uuid, p_loans_only boolean)`
An RPC, listed with the views it reads beside. The Activity tab (#91): one row per `activity` row,
newest first, with what the app needs to say it in one line. It shows only spaces the caller is an
accepted, active member of and loans they are an accepted party to. A departed member, an outsider,
a pending claimant and an unverified user see no rows; anon cannot call it. Pending claimants can
still review the claim itself through the tables.

It starts from the caller's own spaces and loans, not from `activity` at large: each contributes
at most one page through `activity (space_id | loan_id, created_at, id)`, so the cost follows the
caller's memberships, not other tenants' traffic. Security definer with a fixed search path; it
makes the membership checks itself and names a person only where `profiles` RLS would.

| Column | Type | Meaning |
| --- | --- | --- |
| `id`, `created_at`, `action` | bigint, timestamptz, text | The `activity` row |
| `kind` | text | `expense`, `settlement`, `loan`, `repayment`, or `member` (a `rejected` claim) |
| `space_id`, `space_name` | uuid, text | The space; null for loan rows |
| `expense_id`, `loan_id`, `repayment_id` | uuid | What the row is about |
| `by_me` | boolean | The caller did it |
| `actor_name` | text | Who did it: their space label, profile name or number; on loan rows the other party, null when it was you |
| `counterparty` | text | Loan rows: the other party's name or number |
| `description` | text | The expense's description after the change; for `rejected`, the number that declined |
| `amount_minor` | bigint | The amount after the change (a loan's principal for loan rows) |
| `before_description`, `before_amount_minor` | text, bigint | `edited` rows only: the values before |
| `status` | text | Settle-ups and repayments as they stand now: `pending`, `confirmed`, `disputed`, or `deleted` |
| `my_side` | text | Settle-ups and repayments: `in` (to the caller), `out` (from the caller), else null |
| `questions` | jsonb | `edited` rows in a space: members' 'Question this' notes, oldest first, as `[{"by_me": bool, "name": text, "note": text, "created_at": timestamptz}]`; null when there are none |

Rows are ordered by `(created_at, id)` descending. `created_at` is when the change happened (its
transaction's start), so a transaction that began earlier but committed later still sorts by its
time, not its id. Page by that pair: pass the `created_at` and `id` of the last row shown, and the
next page starts strictly below it.

The paging contract:
- **Strict and stable:** for rows committed before the first page loaded, every row comes back
  exactly once, in order, however many pages are read.
- **Late commits wait for refresh:** a transaction that commits after the client has paged past its
  `created_at` sorts behind the cursor, so later pages do not include it. It appears when the
  client reloads from the top (Activity's pull-to-refresh, which drops the cursor). Rows newer than
  the first page likewise appear only on refresh.
`p_limit` defaults to 30 and is held to 1–100; both cursor arguments null means the first page.

Filters (#109), both optional: `p_space_id` keeps one space's rows and `p_loans_only` keeps loan rows
(loans and repayments). They narrow the caller's own spaces and loans before the page is built, so a
filter never shows more than the unfiltered feed does (a space the caller is not in gives no rows),
`p_limit` counts matching rows, and the order, cursor and paging contract above are unchanged. Both
together match nothing. A call that names only the first three arguments is unfiltered.

```
POST /rest/v1/rpc/activity_feed  {"p_limit": 30}
POST /rest/v1/rpc/activity_feed  {"p_limit": 30, "p_before_at": "2026-11-09T08:30:00.123456+00:00", "p_before_id": 4211}
POST /rest/v1/rpc/activity_feed  {"p_limit": 30, "p_space_id": "<space id>"}
POST /rest/v1/rpc/activity_feed  {"p_limit": 30, "p_loans_only": true}
```

### `activity_seen`
A table, listed with the feed it belongs to (#109): one row per user, `seen_at`, the `created_at` of
the newest feed entry they have seen. RLS shows a user only their own row, and only
`mark_activity_seen` writes it. Among the newest 100 feed entries, the bell counts what is newer
than `seen_at` (everything when there is no row): each entry that is not the caller's own, and each
question (`questions[].created_at`) someone else asked about an edit the caller made. A question
therefore rings for the editor it is addressed to and for no other member. It is on the server, not
the device, so opening Activity on one phone clears the bell on the caller's others.

```
GET /rest/v1/activity_seen?select=seen_at
```

### `needs_you`
What waits for the caller's answer, under the same rules as `activity_feed`: settle-ups they are
the payee of (`pending_settlements` with `awaiting_me`) and pending repayments the other side of
their loan recorded. Activity's 'Needs you' filter and top card.

| Column | Type | Meaning |
| --- | --- | --- |
| `kind`, `id` | text, uuid | `settlement` (an `expenses` id) or `repayment` (a `loan_repayments` id) |
| `space_id`, `space_name` | uuid, text | Settle-ups only |
| `loan_id` | uuid | Repayments only |
| `counterparty` | text | Who paid: their name or number |
| `amount_minor`, `paid_on`, `created_at` | bigint, date, timestamptz | What, when paid, when recorded |

Answer through `confirm_settlement` / `dispute_settlement` or `confirm_repayment` /
`dispute_repayment`.

```
GET /rest/v1/needs_you?order=created_at.desc
```

## Functions

### Invite links (#104)

`issue_invite(p_kind, p_subject_id, p_idempotency_key)` is authenticated-only. A verified,
accepted space member may issue for a pending `space_members.id`; an accepted loan party may issue
for the other pending side of a loan. It returns a server-generated 256-bit token. The token expires
after 14 days, is single-use, and only its SHA-256 digest is stored. Same key and payload rotates
the live bearer token (invalidating the prior token); a changed payload is `PT409`. A target may
have at most five live links. The app retains an issue key only across a failed/ambiguous call;
after success, re-sharing uses a fresh key so the previously sent link remains live. Issue and
redeem are limited to 20 calls per verified user per hour; failed malformed, unknown, unavailable,
and wrong-phone redemption attempts count. The database has no trusted client IP, so this is a
per-verified-user backstop in addition to gateway IP throttling. The stable issue hints are
`invite_target_limit` and `invite_rate_limited`.

`inspect_invite(p_token)` is callable by `anon` and `authenticated`. A live token returns only
`kind`, `inviter_name`, `subject_name`, and `masked_phone`; it never returns ids, membership,
amounts, balances, loan terms, or an unmasked phone. Tokens must be exactly 64 lower-case hex
characters. Invalid, expired, used, declined, revoked, and former-party tokens return no row.

`redeem_invite(p_token, p_idempotency_key)` requires the authenticated caller's currently verified
phone to equal the invite target. It consumes the token and accepts the existing claim atomically.
A same-key replay returns `redeemed`; other expected outcomes are the privacy-safe result values
`wrong_phone`, `invite_unavailable`, and `invite_rate_limited`, which allows failed-attempt quota
writes to commit. Another use is refused. `decline_invite(p_token,
p_idempotency_key)` is capability-based so “This isn't me” works before sign-in: it consumes only
that link and records privacy-safe, link-only rejection activity for the inviter. It never rejects
or unlinks the underlying claim, so the verified target can still accept or reject it normally.
Live links are explicitly revoked when their issuer leaves the space or ceases to be a loan party.

The app currently shares `settlo://join/<token>`. `SETTLO_INVITE_HOST` is the single switch to build
`https://<host>/join/<token>` after the owner supplies a verified domain; universal/app-link platform
entitlements are deliberately deferred until then.

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
| `is_settlement` | boolean | Optional, default `false`. A settle-up: exactly one payer (who paid) and one split (the payee), different members, else `22023` hint `settlement_shape`. Pending until the payee confirms it, unless the caller is the payee (see [Settle-ups](#settle-ups-78)) |
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

## Space and expense mutations (#59)

Same rules as the RPCs above: `authenticated` only, verified callers, the same error codes, and
payload-bound idempotency. `add_expense` and `create_space` keep their key on the row they create;
these keep theirs server-side (`private.idempotency_keys`, no client access), unique **per user**
(ADR 0004). A caller reusing a key for another payload or another of these RPCs gets `PT409`; another
user's identical key never collides. A concurrent call with the same key waits for the first to
commit, then replays it (same payload) or conflicts.

**Replay window (#70).** A key in `private.idempotency_keys` is honoured for **30 days** from its first
use; a pg_cron job (`purge-idempotency-keys`, daily at 03:17 UTC) then deletes it. Within the window a
replay returns without writing; after it, the same key runs as a new call (so it may apply again or
fail on the current state, e.g. `already_member`). Clients must not replay a mutation more than 30
days after first sending it: drop it and refresh from the server (ADR 0004). Keys held on the rows
that `add_expense` and `create_space` create are never purged.

Edits and deletes are open to the expense's **creator or a space owner**; the `expenses` update
policy matches. Payers and splits are written **only** by `add_expense` and `update_expense`: clients
have no insert, update or delete privilege on `expense_payers` / `expense_splits`, so no balance can
change without an `activity` row.

A departed membership's balance is frozen: an edit, delete or restore of an expense that involves a
member who has left is refused (`22023`, hint `departed_member`). Leaving and allocation changes lock
the member rows involved, so a concurrent expense and leave cannot both succeed.

History: every edit and delete writes an `activity` row (`edited` / `deleted`) whose `before` is the
full prior expense, including `payers` and `splits` arrays; `after` is the new expense row. The new
payers and splits are the current rows (and the next edit's `before`).

Further hints, all on `22023`:

| Hint | When |
| --- | --- |
| `balance_not_zero` | A member with a non-zero balance would leave or be removed |
| `last_owner` | The space's last active owner would leave, be removed or be demoted |
| `not_accepted` | `set_member_role` would make a pending member an owner |
| `departed_member` | An edit, delete or restore of an expense whose payers or splits include a departed membership |
| `already_member` | `add_space_members` names an active member's phone |
| `invalid_vpa` | A malformed UPI id |

### `update_expense(p jsonb)`
Replaces an expense's fields, payers and splits in one transaction and returns its id. `p` is the
`add_expense` payload with `expense_id` instead of `space_id`, and every rule from `add_expense`
(payers, splits, `equal` recomputation, percent/shares allocation) applies. Omitting `spent_on` keeps
the current date; other omitted optional fields take the `add_expense` defaults. The fingerprint is
`add_expense`'s plus `expense_id`.

- `42501`: not the creator or an owner, not an accepted member, the space is deleted, or the expense
  is unknown.
- `22023`: invalid payload, the expense is deleted, or it involves a departed member
  (`departed_member`); for a settle-up, `settlement_kind`, `settlement_final` or `settlement_shape`
  (#78).
- Concurrent edits of one expense run one after the other (row lock), so each `activity` row has a
  consistent before image.

```
POST /rest/v1/rpc/update_expense
{"p": {"expense_id": "c4a1e7f2-…", "idempotency_key": "5d2e…", "description": "Groceries and gas",
       "amount_minor": 12000, "split_type": "exact",
       "payers": [{"member_id": "<Asha>", "amount_minor": 12000}],
       "splits": [{"member_id": "<Asha>", "amount_minor": 6000}, {"member_id": "<Bilal>", "amount_minor": 6000}]}}

200 "c4a1e7f2-…"
```

### `delete_expense(p_expense_id uuid, p_idempotency_key uuid)`
Soft-deletes the expense (`deleted_at`): it stops counting in every view and is frozen (only a
restore could change it). Returns nothing. Deleting an already-deleted expense with a new key is
`22023`, as is one that involves a departed member (`departed_member`) or a confirmed or disputed
settle-up (`settlement_final`, #78); a replay with the same key succeeds.

```
POST /rest/v1/rpc/delete_expense  {"p_expense_id": "c4a1e7f2-…", "p_idempotency_key": "8a1f…"}
```

### `add_space_members(p_space_id uuid, p_members jsonb, p_idempotency_key uuid)`
Adds members by phone to a space the caller is an accepted, active member of. `p_members` is
`create_space`'s format (`[{"phone": "+91…", "name": "…"}]`), non-empty, distinct E.164 phones. New
rows are `member`s, pending until each number verifies and accepts (#9). An active member's phone is
`22023` with hint `already_member`.

A departed member's phone can be added again (#70). It gets a **fresh membership**: a new
`space_members` row and id, a pending `member` like any new number. The departed row stays departed
with its history and its balance (normally zero; a rejected claim departs whatever it is), and no RPC
or direct write can make its allocations live again: editing, deleting or restoring an expense whose
payers or splits include it is `22023` with hint `departed_member`. So a rejoining member starts at
zero and never inherits a pre-departure balance. A phone (and a user) has at most one active row per
space; departed rows may repeat. A direct `left_at` update back to null is `42501`.
The fingerprint is the space and the members sorted by phone. Returns nothing.

```
POST /rest/v1/rpc/add_space_members
{"p_space_id": "6f1c…", "p_members": [{"phone": "+919800000010", "name": "Yash"}], "p_idempotency_key": "1b2c…"}
```

### `leave_space(p_space_id uuid, p_idempotency_key uuid, p_member_id uuid default null)`
Without `p_member_id` the caller leaves; with it an owner removes that member (`42501` for anyone
else). Leaving sets `left_at`; history stays. Only at a **zero balance** (`space_member_balances`):
otherwise `22023` with hint `balance_not_zero`, so the client sends the user to settle up first. The
space's last active owner cannot leave or be removed (`22023`, hint `last_owner`); a sole owner hands
over with `set_member_role` first. Both rules are
a trigger on `space_members`, so a direct `left_at` update is held to them too, and they hold under
concurrency: departures in a space are serialised on the space row, and a leave and an expense
naming the same member wait for each other. The key is
checked before membership, so a replay returns after the caller has left. Returns nothing.

```
POST /rest/v1/rpc/leave_space  {"p_space_id": "6f1c…", "p_idempotency_key": "9c3d…"}

400 {"code": "22023", "hint": "balance_not_zero", "message": "member … has a balance of -500 and cannot leave until it is settled", …}
```

### `set_member_role(p_space_id uuid, p_member_id uuid, p_role member_role, p_idempotency_key uuid)`
An owner promotes an active member to `owner` or demotes an owner (themselves included) to `member`.
Setting the current role is a no-op. Returns nothing. The fingerprint is the space, member and role.

- `42501`: the caller is not an accepted, active owner of the space (checked again after the locks
  below, so an owner demoted concurrently is refused).
- `22023`: a missing argument, or `p_member_id` is not an active member of the space; hint
  `not_accepted` to promote a pending member; hint `last_owner` to demote the space's last accepted,
  active owner.
- Concurrency: like a leave, it locks the member row, then the space row, so role changes and
  departures in a space run one after the other and the space always keeps an owner.
- The key is checked before ownership, so a replay returns after the caller has stepped down.

Hand-over: the sole owner promotes someone, then demotes themselves or leaves.

```
POST /rest/v1/rpc/set_member_role
{"p_space_id": "6f1c…", "p_member_id": "<Bilal>", "p_role": "owner", "p_idempotency_key": "4e5f…"}
```

### `update_profile(p_name text, p_upi_id text)`
Sets the caller's name (required, trimmed, at most 100 characters) and UPI id. A null or blank
`p_upi_id` clears it. A UPI id must look like `handle@psp`: 1–255 of `A–Z a–z 0–9 . _ -`, `@`, then
2–64 letters (`public.is_vpa`); otherwise `22023` with hint `invalid_vpa`. `profiles.upi_id` has the
same check, so a direct write of a malformed id fails with `23514`. No idempotency key: a replay
writes the same values.

```
POST /rest/v1/rpc/update_profile  {"p_name": "Asha K", "p_upi_id": "asha.k@okaxis"}
```

### `delete_account()` (#9, #74)
Deletes the caller's account. No arguments: it acts on `auth.uid()` only, verified or not; `42501`
without a session. Security definer. Returns nothing.

- The profile stays as a tombstone, because shared history references it: `name` becomes
  `'Deleted user'`, `upi_id` and `phone` are cleared, `deleted_at` is set.
- The caller's `friends` rows are deleted; other people's entries for the caller keep the number they
  typed and lose `friend_id`. Claims the caller never accepted are unlinked. Invite links the caller
  issued are revoked.
- The `auth.users` row is deleted, and with it sessions, refresh tokens, idempotency keys and the
  lookup quota. The number is free at once.
- Nothing else changes: memberships the caller accepted, expenses, allocations, loans, repayments,
  settle-ups, dispute reasons and activity stay as they are for the other members.

Idempotent: the access token outlives the auth user, and a second call returns normally and writes
nothing. Until that token expires it reads nothing. The client should drop its session locally
(`signOut(scope: local)`); a server sign-out has no user to act on.

The auth row is locked first, so a concurrent verification of the same user either commits before
the deletion (which then releases what it linked) or finds no user. The same lock is the write
barrier: every write by the `authenticated` role (each mutating RPC, and direct table writes) first
takes a key-share lock on the caller's auth row. A write that started before the deletion commits
first and stays as history. One that arrives during or after it is refused with `42501`, hint
`account_deleted`, so nothing is written in a deleted account's name. A write and a deletion that
each hold a row the other needs can deadlock (`40P01`); both are safe to retry. The number signing up again is a
new user: it is linked only to rows nobody had accepted, as pending claims.

```
POST /rest/v1/rpc/delete_account  {}
```

## Loans (#87)

Same rules as the RPCs above: `authenticated` only, verified callers, the same error codes, and
payload-bound idempotency. Every loan RPC claims its key in `private.idempotency_keys`, so a key is
unique per user across all of them and the #59 RPCs: a key reused for another RPC is `PT409`.
`create_loan` and `record_repayment` also use the key as the new row's id (as `create_space`), so the
client can queue repayments against a loan it created offline, and keep the fingerprint on that row,
which answers a replay after the 30-day purge (#70).

Two-sided confirmation: a repayment is recorded **pending** by one party and only the **other** party
confirms or disputes it, once. Both outcomes are final. Only confirmed repayments count
(`loan_summaries.repaid_minor`); a disputed one stays visible with its reason and never counts. The
`loan_repayments` guard trigger (#7) holds direct table writes to the same rules, including the
`overpayment` check on record. v1 is interest free: a repayment is all principal.

Closing: when confirmed repayments reach the principal, the confirmation closes the loan
(`closed_at`). That is the only way a loan closes: clients cannot write `closed_at` (no column
privilege, no update policy on `loans`), so a lender can neither close a loan early nor reopen one.
Nothing can be recorded on a closed loan, and no confirmation may take the confirmed total past the
principal.

Activity (`activity.loan_id`): `created` (after: the loan), `recorded` (after: the repayment),
`confirmed` / `disputed` (before and after: the repayment), `closed` (before and after: the loan; a
confirmation that repays the loan logs `confirmed` then `closed`).

Who may call what:

| | Lender | Borrower | Pending claimant | Outsider / unverified / anon |
| --- | --- | --- | --- | --- |
| `create_loan` | any verified user, as either side | | | `42501` |
| `record_repayment` | yes | yes | `42501` | `42501` |
| `confirm_repayment`, `dispute_repayment` | only what the borrower recorded | only what the lender recorded | `42501` | `42501` |

A pending claimant is a number the loan was recorded against that has verified but not yet accepted
the claim (`accept_claim('loan', id)`, #9): it can read the loan but write nothing.

Further hints:

| Code | Hint | When |
| --- | --- | --- |
| `22023` | `interest_not_supported` | `create_loan` with an `interest_type` other than `none` |
| `22023` | `overpayment` | A repayment over what is outstanding (principal minus confirmed), or a confirmation that would pass the principal |
| `22023` | `loan_closed` | `record_repayment` on a closed loan |
| `22023` | `paid_on_before_start`, `paid_on_future` | A repayment dated before its loan's `start_on` or after today in India |
| `22023` | `reference_invalid` | A repayment reference over 64 code points after trimming, or with a `Cc` / `Cf` character (see `record_repayment`) |
| `22023` | `not_pending` | Confirming or disputing a repayment already confirmed or disputed |
| `42501` | `own_record` | Confirming or disputing a repayment your own side recorded |

### `create_loan(p jsonb)`
Creates a loan between the caller and `counterparty_phone` and returns its id (the key). The
counterparty may have no account: their side is a pending claim until that number verifies and
accepts (#9). Nothing about the counterparty is revealed to the caller before then.

| Field | Type | |
| --- | --- | --- |
| `idempotency_key` | uuid | Required; becomes the loan id |
| `direction` | text | Required: `lent` (caller is the lender) or `borrowed` |
| `counterparty_phone` | E.164 | Required; not the caller's own number |
| `principal_minor` | bigint | Required, > 0 |
| `installment_minor`, `due_day` | bigint, 1–28 | Both for a `monthly` loan (instalment ≤ principal), neither for `flexible` |
| `start_on` | date | Default: today in India |
| `interest_type` | text | Optional; only `none` in v1 |

The fingerprint is every field above except the key, with `start_on` as sent. A replay with another
payload, or a key that is another user's loan id, is `PT409`.

```
POST /rest/v1/rpc/create_loan
{"p": {"idempotency_key": "3e7a…", "direction": "lent", "counterparty_phone": "+919800000002",
       "principal_minor": 1000000, "installment_minor": 100000, "due_day": 5, "start_on": "2026-11-10"}}

200 "3e7a…"
```

### `record_repayment(p jsonb)`
Either accepted party records a repayment; it is pending until the other party answers. Returns the
repayment id (the key).

| Field | Type | |
| --- | --- | --- |
| `loan_id` | uuid | Required |
| `idempotency_key` | uuid | Required; becomes the repayment id |
| `amount_minor` | bigint | Required, > 0, at most the outstanding principal (`overpayment`) |
| `paid_on` | date | Default: today in India; from the loan's `start_on` to today in India (`paid_on_before_start`, `paid_on_future`) |
| `method` | `upi`, `cash`, `bank`, `other` | Optional |
| `reference` | text | Optional (e.g. a UPI transaction id); see the reference rule below (`reference_invalid`) |

The reference rule, applied in this order (clients mirror it exactly):

1. Trim Unicode `White_Space` from both ends: U+0009–000D, U+0020, U+0085, U+00A0, U+1680,
   U+2000–200A, U+2028, U+2029, U+202F, U+205F, U+3000. Whitespace inside is kept. Empty after
   trimming is stored as null.
2. At most 64 code points (not UTF-16 units or grapheme clusters).
3. No Unicode `Cc` or `Cf` character anywhere (Unicode 16): U+0000–001F, U+007F–009F, U+00AD,
   U+0600–0605, U+061C, U+06DD, U+070F, U+0890–0891, U+08E2, U+180E, U+200B–200F, U+202A–202E,
   U+2060–2064, U+2066–206F, U+FEFF, U+FFF9–FFFB, U+110BD, U+110CD, U+13430–1343F, U+1BCA0–1BCA3,
   U+1D173–1D17A, U+E0001, U+E0020–E007F. U+FEFF is refused, not trimmed, even at an end.

Pending repayments do not reduce what is outstanding, so two pending repayments may together exceed
it; whichever is confirmed second is then refused (`overpayment`) and can be disputed. A replay
returns the id even after the loan has closed.

```
POST /rest/v1/rpc/record_repayment
{"p": {"loan_id": "3e7a…", "idempotency_key": "7b1c…", "amount_minor": 100000, "method": "upi",
       "paid_on": "2026-12-05", "reference": "UPI 4321…"}}

200 "7b1c…"
```

### `confirm_repayment(p_repayment_id uuid, p_idempotency_key uuid)`
The other party confirms a pending repayment. Final. Closes the loan if it is now fully repaid.
Returns nothing. The key is checked first, so a replay succeeds after the repayment is no longer
pending; the fingerprint is the repayment id.

- `42501`: not an accepted party, or `own_record`.
- `22023`: `not_pending`, or `overpayment`.
- Concurrency: a confirmation and a dispute of the same repayment (two devices) run one after the
  other on the repayment row; the second is `not_pending`.
- Security definer, so the shared confirm/dispute step (`private.settle_repayment`) stays
  server-only; every check is made against the caller's verified id, as RLS would.

```
POST /rest/v1/rpc/confirm_repayment  {"p_repayment_id": "7b1c…", "p_idempotency_key": "c2d4…"}
```

### `dispute_repayment(p_repayment_id uuid, p_reason text, p_idempotency_key uuid)`
The other party disputes a pending repayment with a reason (trimmed, 1–500 characters, else
`22023`). Final: the repayment stays visible with `dispute_reason` and never counts; the payer
records a corrected one instead. Same errors and concurrency as `confirm_repayment`. The fingerprint
is the repayment id and the trimmed reason.

```
POST /rest/v1/rpc/dispute_repayment
{"p_repayment_id": "7b1c…", "p_reason": "Not received yet", "p_idempotency_key": "e5f6…"}
```

## Settle-ups (#78)

A settle-up is an expense with `is_settlement`: one payer pays one payee. It follows the loan
repayment model (#87). Recorded by anyone but the payee, it is **pending**; only the payee confirms
or disputes it, once, and both outcomes are final. When the payee records it with `add_expense` (or
corrects a pending one with `update_expense`) it is confirmed at once. Only confirmed settle-ups count
in `space_member_balances`; pending ones are listed in `pending_settlements`, and a disputed one stays
visible with its reason and never counts. Settle-ups recorded before #78 were confirmed by the
migration.

`expenses` gains `settlement_status` (`pending`, `confirmed`, `disputed`; null for spending), derived
from `confirmed_by` / `confirmed_at` / `disputed_by` / `disputed_at` / `dispute_reason`. Clients
cannot write these columns. A trigger holds every write, the RPCs and direct updates alike, to the
rules: an expense never changes between spending and a settle-up (`22023` hint `settlement_kind`), and
a confirmed or disputed settle-up cannot be edited, deleted or restored (`22023` hint
`settlement_final`). A pending one may still be edited or deleted by its creator or a space owner.

One pending settle-up per payer and payee: recording another from the same payer to the same payee
while one is pending is `22023` hint `settlement_pending`, whoever records it; it is the same payment
recorded twice. Concurrent records of a pair are serialised (a transaction-scoped advisory lock), so
of two at once the second is refused. Once the payee answers, a new one may be recorded; a disputed
one's debt is owed again.

Clients net the caller's own pending settle-ups (`pending_settlements` where the caller is the payer)
out of the payments they offer, and show each as waiting for the payee; balances stay confirmed-only.

Confirming changes both members' balances, so like an edit it is refused when the payer has left
(`22023` hint `departed_member`); a member may leave while a settle-up is pending, as it does not
count.

Activity: `created`, then `confirmed` / `disputed` (before and after: the expense). A settle-up the
payee records logs `created` then `confirmed`.

| | Payee | Payer or other member | Pending claimant | Outsider / unverified / anon |
| --- | --- | --- | --- | --- |
| `confirm_settlement`, `dispute_settlement` | yes, while pending | `42501` hint `not_payee` | `42501` | `42501` |

Further hints:

| Code | Hint | When |
| --- | --- | --- |
| `22023` | `settlement_shape` | A settle-up without exactly one payer and one other payee |
| `22023` | `settlement_pending` | Recording (or editing into) a settle-up from a payer to a payee while another between them is pending |
| `22023` | `settlement_kind` | Turning spending into a settle-up or back |
| `22023` | `settlement_final` | Editing, deleting or restoring a confirmed or disputed settle-up |
| `22023` | `not_pending` | Confirming or disputing a settle-up that is already answered or deleted |
| `22023` | `settlement_changed` | Confirming an amount or payer the settle-up no longer has (it was edited since it was shown) |
| `42501` | `not_payee` | Confirming or disputing as anyone but the payee |

### `confirm_settlement(p_expense_id uuid, p_amount_minor bigint, p_payer_member_id uuid, p_idempotency_key uuid)`
The payee confirms a pending settle-up; it counts from now on. Final. Returns nothing. The payee
sends the amount and payer they were shown: a pending settle-up can still be edited, and an edit that
lands first is refused as `settlement_changed` rather than confirmed unseen. The key is claimed in
`private.idempotency_keys` first, so a replay succeeds after the settle-up is no longer pending; the
fingerprint is the expense id, amount and payer.

- `42501`: not an accepted member of the space, not a settle-up, or `not_payee`.
- `22023`: a missing argument, `not_pending`, `settlement_changed`, or `departed_member`.
- Concurrency: a confirmation and a dispute of the same settle-up (two devices) lock the expense row
  one after the other; the second is `not_pending`. An edit or delete waits the same way.
- Security definer, so the shared step (`private.answer_settlement`) stays server-only; every check
  is made against the caller's verified id, as RLS would.

```
POST /rest/v1/rpc/confirm_settlement
{"p_expense_id": "0b9d…", "p_amount_minor": 50000, "p_payer_member_id": "<Rahul>", "p_idempotency_key": "c2d4…"}
```

### `dispute_settlement(p_expense_id uuid, p_reason text, p_idempotency_key uuid)`
The payee disputes a pending settle-up with a reason (trimmed, 1–500 characters, else `22023`).
Final: it stays visible with `dispute_reason` and never counts; the payer records a corrected one.
Same errors and concurrency as `confirm_settlement`, without `departed_member` and
`settlement_changed` (a dispute changes no balance). The fingerprint is the
expense id and the trimmed reason.

```
POST /rest/v1/rpc/dispute_settlement
{"p_expense_id": "0b9d…", "p_reason": "Not received yet", "p_idempotency_key": "e5f6…"}
```

## Activity (#109)

### `mark_activity_seen(p_at timestamptz)`
Records that the caller has seen the feed up to `p_at`, the newest `created_at` shown, of an entry
or of a question on one.
The cursor only moves forward and is held to now, so the call is idempotent: a replay, or two phones
answering out of order, changes nothing. No idempotency key. An unverified caller gets `42501`, a
null time `22023`; anon cannot call it.

### `question_activity(p_activity_id bigint, p_note text)`
'Question this': leaves a short note on an `edited` row for whoever made the edit. The caller must
be an accepted, active member of the row's space and not the editor; anything else, a missing row
included, gets the same `42501`, so the call cannot probe for rows. The note is trimmed and must be
1 to 280 characters (`22023`).

Indian phone numbers in it are replaced with `••••` on write, by `private.redact_phones`. The
server is the authority here: it starts from the app's `redactPhones` rule and is stricter. A
number is 10 digits, optionally led by `+91`, `91` or `0`, with up to two spaces, dashes, dots or
parentheses between digits. It is looked for in a folded copy of the note: NFKC first, so circled,
superscript, subscript, parenthesised and fullwidth digits read as plain ones; then any script's
digits (`Nd`), any space (`Zs`) and any dash (`Pd`) are folded; and nonspacing and enclosing marks
(`Mn`, `Me`, which include U+034F and the variation selectors U+FE00–FE0F and U+E0100–E01EF) and
invisible format characters (`Cf`) are dropped. The match is then redacted in the original text.
So a client that redacts nothing still cannot store a number. The helper also carries the rule's
exemption for a reference that is exactly 12 contiguous digits (a UTR); notes are free text and do
not use it. The app still redacts before sending and when showing a note, as a second line; it
does not fold lookalike digits or marks, which is why the server does.

One note per member per row: asking again replaces the caller's note. The same note again changes
nothing, so a replay is harmless and there is no idempotency key; a changed note counts as asked
now. Notes are stored outside the API schema and are read only as
`activity_feed.questions`, which shows them to exactly the people who see the row: accepted, active
members of that space. A member who leaves stops seeing them; their own note stays for the others.

```
POST /rest/v1/rpc/mark_activity_seen  {"p_at": "2026-11-09T08:30:00.123456+00:00"}
POST /rest/v1/rpc/question_activity   {"p_activity_id": 4211, "p_note": "Why did this go up?"}
```

## Claims (#9, #116)

A membership or loan side recorded against a number is a claim until its holder answers it. Both
answers are final.

### `accept_claim(p_kind text, p_id uuid, p_idempotency_key uuid)`
### `reject_claim(p_kind text, p_id uuid, p_idempotency_key uuid)`
`p_kind` is `space_member` (then `p_id` is the `space_members.id`) or `loan` (the `loans.id`).
Accepting links the caller and stamps the acceptance; rejecting ('This isn't me') unlinks the number
for good and writes a `rejected` activity row that names the number, not the caller.

The key follows ADR 0004 and #59: it is claimed in `private.idempotency_keys` (unique per user,
bound to the function and to `kind` + `id`) before anything else, so a replay returns without
writing even though the claim is no longer pending. A refused call rolls its key back with it.

- `22023`: `p_kind`, `p_id` or the key is null.
- `42501`: the caller has no verified phone, or has no pending claim on that row (unknown kind or id,
  someone else's claim, or one already answered under another key).
- `PT409` (`idempotency_conflict`): the key was used with another function, kind or id.
- Replay window (#70): keys are honoured for 30 days. After that a replay runs as a new call and is
  refused with `42501`; the app drops a queued answer first sent more than 29 days ago.

The two-argument `accept_claim(p_kind, p_id)` and `reject_claim(p_kind, p_id)` remain for
`redeem_invite` and older clients. They are not idempotent: a retry after a lost response is refused
with `42501`, so new callers must pass a key.
