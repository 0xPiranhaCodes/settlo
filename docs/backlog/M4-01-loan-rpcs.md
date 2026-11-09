Loan RPCs: create, record repayment, confirm, dispute
area:backend,type:feature,agent:claude
M4 Loans
**Owner:** Principal Backend · **Depends on:** #7, #11 · **Contract:** ADR 0004 (payload-bound idempotency), two-sided confirmation (context pack)

## Acceptance criteria
- [ ] `create_loan(p jsonb)`: direction (lent/borrowed), counterparty E.164, principal_minor, installment_minor, due_day, start_on; interest fixed to none in v1; counterparty may be unregistered (claim flow as for spaces)
- [ ] `record_repayment(p jsonb)` by either party; `confirm_repayment` and `dispute_repayment` only by the other party; a confirmed repayment is final; disputed ones stay visible with a reason
- [ ] Closing: a loan closes when confirmed repayments reach principal; overpayment refused
- [ ] Every change writes an activity row with before/after values; docs/api.md updated

## Test plan
pgTAP allowed/denied per RPC (lender, borrower, outsider, pending claimant, anon); recorder cannot confirm own repayment; idempotent replay and PT409; dblink race confirm-vs-dispute; loan_summaries correct after each step.
