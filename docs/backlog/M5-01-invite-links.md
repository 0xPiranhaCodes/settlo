Invite links and the Join screen
area:flutter,type:feature,agent:claude
M5 Platform surfaces and offline
**Owner:** Principal Flutter + Backend · **Canvas:** Join (note n43) · **Depends on:** domain for verified links (owner)

## Acceptance criteria
- [ ] Space and loan invites produce a link (`/join/:token`, single-use or expiring, server-issued) shared through WhatsApp; the loan WhatsApp text gets the link (removes the M6 shortcut in new_loan_sheet)
- [ ] Join screen: who added you, to what, recorded against your number, no amounts until verified; 'This isn't me' exit
- [ ] iOS universal links and Android app links once the owner's domain is set; custom scheme fallback until then
- [ ] RLS: a token reveals nothing beyond the Join copy; expired/used tokens refused

## Test plan
pgTAP for token issue/redeem/expiry/reuse; widget tests for Join and 'This isn't me'; deep-link routing tests; goldens 390/360.
