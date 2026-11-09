Monorepo scaffold: Flutter app, workspace packages, strict lints
area:infra,type:chore,agent:claude
M0 Foundations
**Owner:** Principal Architect · **Canvas:** n/a

## Context
Context pack › Architecture. Feature-first packages so principals never edit the same files.

## Acceptance criteria
- [ ] `app/` Flutter app, bundle id `app.settlo` (iOS, min 16.1) and applicationId `app.settlo` (Android, minSdk 26)
- [ ] Dart pub workspace (or Melos) with packages: `core`, `local`, `platform`, `features/{auth,spaces,expenses,balances,loans,settle,activity,profile}`
- [ ] Riverpod (codegen), go_router, freezed, json_serializable, drift, google_fonts wired as deps where used; `build_runner` script at root
- [ ] `very_good_analysis` (or equivalent strict) lints; `flutter analyze` clean
- [ ] `docs/ownership.md`: path → owning role map

## Test plan
`flutter analyze` and `flutter test` pass at root; app boots to an empty route on iOS sim and Android emulator.

## Out of scope
Screens, theme, CI.
