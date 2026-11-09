ADRs 0001–0005: stack, package boundaries, money, offline sync, review rules
area:infra,type:adr,agent:claude
M0 Foundations
**Owner:** Principal Architect

## Acceptance criteria
- [ ] 0001 Stack (records the already-taken decisions; links Context pack)
- [ ] 0002 Package boundaries and dependency direction (features → core/local, never feature → feature)
- [ ] 0003 Money as integer paise; equal-split remainder to payer; greedy simplification on device
- [ ] 0004 Offline: drift mirror + `pending_mutations` queue with idempotency keys; server is source of truth
- [ ] 0005 Dependency policy: new dependency needs an ADR

## Test plan
Reviewer checks each ADR states context, decision, consequences.
