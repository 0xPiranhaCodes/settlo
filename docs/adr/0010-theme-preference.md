# 0010 Persist the theme preference with `shared_preferences`

## Status
Accepted (9 Nov 2026)

## Context
Issue #64 adds a system, dark and light appearance choice that must survive app restarts. This is a small device-local scalar preference: it is not shared financial data, does not belong in the drift ledger mirror, and should not be synced to Supabase. `shared_preferences` is already present transitively through `supabase_flutter`, but profile now imports it directly, so ADR 0005 requires recording the dependency.

## Decision
Add `shared_preferences ^2.5.6` directly to `settlo_profile` and store the enum name under `settlo.theme_mode`. Use `SharedPreferencesAsync`, not the legacy cached singleton, behind a `ThemeModeRepository` so tests and a future settings store can replace it without changing widgets.

The feature's tests depend directly on `shared_preferences_platform_interface ^2.4.2` for its official in-memory async implementation. This exercises the same uncached adapter without a device plugin; the package is already part of the `shared_preferences` plugin family in the lockfile.

## Consequences
- A missing, unrecognised, or still-loading preference renders dark, preserving Settlo's dark-first launch and avoiding a light frame over the dark native splash.
- System and light remain explicit choices; a saved system choice follows the platform brightness after it loads.
- Profile owns the preference UI and storage; `app` only watches the exported provider when composing `MaterialApp`.
- This adds no new resolved package to the lockfile because Supabase already brought the plugin family into the app, but it makes the direct dependency and its platform persistence intentional.
