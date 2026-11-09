# 0008 Persist the theme preference with `shared_preferences`

## Status
Accepted (9 Nov 2026)

## Context
Issue #64 adds a system, dark and light appearance choice that must survive app restarts. This is a small device-local scalar preference: it is not shared financial data, does not belong in the drift ledger mirror, and should not be synced to Supabase. `shared_preferences` is already present transitively through `supabase_flutter`, but profile now imports it directly, so ADR 0005 requires recording the dependency.

## Decision
Add `shared_preferences ^2.5.6` directly to `settlo_profile` and store the enum name under `settlo.theme_mode`. Use `SharedPreferencesAsync`, not the legacy cached singleton, behind a `ThemeModeRepository` so tests and a future settings store can replace it without changing widgets.

## Consequences
- The setting follows the system when absent or unrecognised and supports explicit dark and light modes.
- Profile owns the preference UI and storage; `app` only watches the exported provider when composing `MaterialApp`.
- This adds no new resolved package to the lockfile because Supabase already brought the plugin family into the app, but it makes the direct dependency and its platform persistence intentional.
