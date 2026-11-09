# 0004 Offline: drift mirror and `pending_mutations` queue

## Status
Accepted (9 Nov 2026)

## Context
Users add expenses on trips and in flats with bad signal. The app has to read and write offline, but balances shared between people must not diverge or double count when a write is retried. Issue #10 makes the `add_expense(jsonb)` RPC idempotent: a replayed `idempotency_key` is a no-op that returns the same expense id.

## Decision
- **Mirror.** `local` holds a drift (SQLite) mirror of the rows the user can read under RLS. The UI reads only from drift, never straight from Supabase.
- **Queue.** Every write goes into a `pending_mutations` table in the same drift transaction as its optimistic local change. Each row has: `id`, `idempotency_key` (UUID v4, generated once on device when the mutation is created and never regenerated), `kind` (for example `add_expense`), `payload` (the RPC's jsonb), `created_at`, `attempts`, `last_error`.
- **Replay.** On reconnect, and on app start, the queue is sent in `created_at` order, one at a time, to the matching RPC with its `idempotency_key`. A success deletes the row and writes the server's response into the mirror. A network error keeps the row and backs off. A rejection from the server (validation or RLS) drops the row, rolls back its optimistic change, and shows the user what failed.
- **Server is authoritative.** After replay, the mirror is refreshed from the server; server rows overwrite local ones. There is no client-side merge and no last-write-wins on the device.
- Every mutating RPC follows the `add_expense` contract: it takes an `idempotency_key`, and the same key returns the original result without writing again.

## Consequences
- Retrying is always safe, so the client can retry freely after timeouts where it cannot tell whether the write landed.
- Backend (#10 and later RPCs) must store idempotency keys with a unique constraint per user; this ADR is the contract between `local` and `supabase/`.
- Ordered, one-at-a-time replay is slower than batching but keeps dependent writes (create space, then add expense to it) correct. Batching would need a new ADR.
- Optimistic rows can disappear after a rejection; the UI must show that clearly.
- Sync code needs 80% unit coverage (context pack), including replay after a lost response and rejection rollback.
