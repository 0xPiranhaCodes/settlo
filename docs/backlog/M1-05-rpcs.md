RPCs: create_space, add_expense (atomic, idempotent), lookup_phones (hashed)
area:backend,type:feature,agent:claude
M1 Auth and backend core
**Owner:** Principal Backend · **Depends on:** M1-03

## Acceptance criteria
- [ ] `create_space(name, kind, members)` creates space + members in one transaction
- [ ] `add_expense(jsonb)` validates, inserts expense/payers/splits atomically; `idempotency_key` makes replays no-ops
- [ ] `lookup_phones(text[])` takes SHA-256 hashes, returns only registered matches; raw numbers never sent
- [ ] `docs/api.md` documents each RPC with request/response examples

## Test plan
pgTAP: replayed idempotency key returns the same expense id; non-member call rejected.
