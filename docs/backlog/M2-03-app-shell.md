App shell: router, tab navigation, Supabase client, auth guard
area:flutter,type:feature,agent:claude
M2 Design system and app shell
**Owner:** Principal Flutter · **Depends on:** M2-02

## Acceptance criteria
- [ ] go_router with a route per canvas artboard (placeholder screens for later milestones), shell route hosting the tab bar (Home, Spaces, Loans, Activity)
- [ ] Supabase client initialised from `--dart-define-from-file=.env.json` (template committed, real file gitignored); never hard-coded
- [ ] Auth guard: signed-out → Welcome; signed-in → Home
- [ ] Riverpod providers for session and client

## Test plan
Widget tests for redirect logic; app boots in both states with a fake session.
