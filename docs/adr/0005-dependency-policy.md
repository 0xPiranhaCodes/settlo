# 0005 Dependency policy

## Status
Accepted (9 Nov 2026)

## Context
Every package is a long-term cost: upgrades, security fixes, build time, and app size. With one pub workspace ([0001](0001-stack.md)), a dependency added anywhere changes the shared `pubspec.lock`. PR #17 review settled that dependencies are not added before code uses them.

## Decision
- A **new** dependency (runtime or dev, Dart or native, including Supabase extensions) needs an ADR that says why, which alternatives were considered, and what it costs. The packages listed in 0001 already have that approval.
- A dependency is added by the first issue whose code imports it, in the package that imports it, never ahead of time. An unused dependency is a request-changes.
- Adding a dependency changes root config (`pubspec.lock`), so the PR needs Architect review ([ownership](../ownership.md)).
- Version constraints use caret ranges (`^x.y.z`); the lockfile is committed. Upgrades that do not change a major version need no ADR.
- Prefer the Dart and Flutter SDKs and existing dependencies over a new package for something that takes a few lines.

## Consequences
- Already in the tree and covered by 0001: `flutter_riverpod` and `go_router` (`app`), `very_good_analysis` (root lints).
- The reviewer checklist item "No new dependency was added without an ADR" can be checked against this list and `docs/adr/`.
- A PR may be blocked on a short ADR; that is the intended cost.
