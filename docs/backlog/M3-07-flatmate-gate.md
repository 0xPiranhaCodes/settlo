Gate M3→M4: flatmate demo integration test and recording
area:qa,type:feature,agent:codex,gate
M3 Spaces end to end
**Owner:** Principal QA · **Depends on:** M3-02…M3-06

## Acceptance criteria
- [ ] integration_test against the local stack: three test numbers sign in, create a space, add 3 expenses with mixed splits, settle up; balances end at zero and fairness matches hand-computed values
- [ ] Simulator screen recording of the flow attached to the PR
- [ ] docs/release.md gate checklist updated

## Test plan
The integration test itself, run on an iOS simulator; recording reviewed by the manager.
