# 0002 Package boundaries and dependency direction

## Status
Accepted (9 Nov 2026)

## Context
Several principals work in parallel. Without fixed boundaries, features import each other, cycles appear, and two agents edit the same files. PR #17 created the packages: `app`, `packages/{core,local,platform}`, `packages/features/{auth,spaces,expenses,balances,loans,settle,activity,profile}`, named `settlo_<dir>`. Path ownership is in [docs/ownership.md](../ownership.md).

## Decision
Allowed dependency edges (arrow = "may depend on"):

```
app ──► features/* ──► core
  │          ├───────► local ──► core
  │          └───────► platform ──► core
  └──► core, local, platform
```

- `core` (theme, router primitives, money, Supabase client) depends on no other Settlo package.
- `local` (drift database, sync queue) and `platform` (live activities, widgets, deep links) depend only on `core`. They do not depend on each other.
- A feature depends only on `core`, `local` and `platform`. **A feature never depends on another feature.**
- `app` composes: it builds the top-level router from routes each feature exports, wires providers, and is the only place that knows every feature.
- Something two features need (a model, a widget, a provider) moves down into `core` or `local`; it is not imported sideways.
- Cross-feature navigation goes by route path through go_router, not by importing the other feature's screen.

## Consequences
- No cycles, and each feature can be built and tested on its own.
- `core` will grow; reviewers keep it to shared primitives, not feature logic.
- Moving a shared type into `core` is a change to a Flutter-owned path; the Architect reviews it.
- Enforcement is by review for now: a feature's `pubspec.yaml` listing another `settlo_<feature>` is a request-changes. A CI check can be added once CI exists (#3).
