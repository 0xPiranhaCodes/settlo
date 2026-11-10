Activity filter chips, bell and 'Question this'
area:flutter,type:feature,agent:claude
M5 Platform surfaces and offline
**Owner:** Principal Flutter · **Canvas:** Activity (note n30)

## Acceptance criteria
- [ ] Per-space and Loans filter chips over the existing activity_feed RPC (server-side filter, same keyset contract)
- [ ] Bell with unread count since last open
- [ ] 'Question this' on an edit opens a short note to the editor, visible on that activity row to members

## Test plan
pgTAP for filtered paging and note authorization; widget tests; goldens 390/360.
