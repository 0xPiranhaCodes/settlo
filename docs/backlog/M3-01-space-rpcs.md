Space and expense mutations: edit, delete, members
area:backend,type:feature,agent:claude
M3 Spaces end to end
**Owner:** Principal Backend · **Depends on:** #10 · **Contract:** ADR 0004 (idempotent, payload-bound keys)

## Acceptance criteria
- [ ] `update_expense(p jsonb)` and `delete_expense(p_expense_id, p_idempotency_key)` (soft delete); only the creator or a space owner; deleted/edited expenses keep history in `activity`
- [ ] `add_space_members(p_space_id, p_members, p_idempotency_key)` and `leave_space` (blocked while the leaver's balance is non-zero; owner can remove a zero-balance member)
- [ ] `update_profile(p_name, p_upi_id)` with VPA format validation
- [ ] Documented in docs/api.md

## Test plan
pgTAP: allowed and denied cases per RPC, idempotent replay, PT409 on payload change, balance invariants after edit/delete, leave blocked with non-zero balance.
