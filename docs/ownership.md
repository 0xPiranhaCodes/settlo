# Ownership

Each path has one owning role (see `docs/roles.md`). Change only paths your role owns; anything else goes through the owner's review. The most specific match wins.

| Path | Owner |
| --- | --- |
| `/` (any path not matched by a more specific row: `pubspec.yaml`, `pubspec.lock`, `analysis_options.yaml`, `.gitignore`, `.env.example`) | Principal Architect |
| `app/` (app-level config: `app/pubspec.yaml`, `app/.metadata`, `app/.gitignore`) | Principal Architect |
| `.github/workflows/` | Principal Architect |
| `docs/adr/` | Principal Architect |
| `scripts/codegen.sh` | Principal Architect |
| `supabase/` | Principal Backend |
| `docs/api.md` | Principal Backend |
| `app/lib/` (including `app/lib/main.dart`) | Principal Flutter |
| `packages/core/` | Principal Flutter |
| `packages/local/` | Principal Flutter |
| `packages/features/*/` | Principal Flutter |
| `app/ios/`, `app/android/` | Principal Mobile Platform |
| `packages/platform/` | Principal Mobile Platform |
| `app/test/`, `packages/**/test/`, `app/integration_test/` | Principal QA |
| `docs/release.md` | Principal QA |

Adding a package or dependency changes root config, so it needs an Architect-approved PR (and an ADR for a new dependency).
