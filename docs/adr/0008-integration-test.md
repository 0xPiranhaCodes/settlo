# 0008 Integration tests: the SDK's integration_test

## Status
Proposed (9 Nov 2026), with the sign-in screens (#29).

## Context
The context pack asks for integration tests (the flatmate and loan flows), and #29 asks for one that signs in with a test number against the local Supabase stack. Widget tests cannot do that: they never initialise Supabase ([0007](0007-supabase-flutter.md)) and run without a device or network. [0005](0005-dependency-policy.md) asks for an ADR for every new dependency, dev ones included; 0001 does not list this one.

## Decision
- Use **`integration_test`** from the Flutter SDK (`sdk: flutter`, no version constraint), as a dev dependency of `app` only. Tests live in `app/integration_test/` and drive the real `main` on a device or simulator.
- They run against the worktree's local stack (`scripts/supabase-local.sh start`) with its settings in `app/.env.json`, and sign in only with the fixed test numbers in `supabase/config.local-dev.toml`. How to run them is in `app/README.md`.
- CI does not run them yet: the `Analyze & test` job runs `flutter test` per member, which covers `test/` only, and has no device. Running them in CI (a simulator job plus the local stack) is a later change to `.github/workflows/`.

## Alternatives considered
- **`flutter_driver`.** The older API, which the SDK now steers away from; `integration_test` reuses the `flutter_test` API we already write.
- **Patrol.** Adds native permission and system-dialog control (useful later for the SMS autofill prompt and contacts), but it is a third-party package with its own CLI. Not needed for the flows we test now.

## Consequences
- The SDK package brings five packages into the lockfile besides itself (`flutter_driver`, `fuchsia_remote_debug_protocol`, `process`, `sync_http` and `webdriver`), all dev-only. Nothing is added to the shipped app.
- Integration tests need a device and a running stack, so they are run by hand until CI gains a job for them.
