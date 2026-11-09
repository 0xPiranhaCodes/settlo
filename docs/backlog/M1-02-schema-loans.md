Schema: loans and repayments with two-sided confirmation
area:backend,type:feature,agent:claude
M1 Auth and backend core
**Owner:** Principal Backend · **Depends on:** M1-01

## Acceptance criteria
- [ ] `loans` per Context pack; `interest_type` enum reserves simple/reducing but v1 constraint allows only `none`
- [ ] `loan_repayments`: `confirmed_by` must be the other party from `recorded_by`; confirmation is final; dispute state
- [ ] Only confirmed repayments count toward outstanding

## Test plan
pgTAP: recorder cannot confirm own repayment; third party cannot confirm; unconfirmed excluded from `loan_summaries`.
