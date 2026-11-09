# 0007 Supabase client: supabase_flutter

## Status
Proposed (9 Nov 2026), with the app shell (#28).

## Context
[0001](0001-stack.md) fixes Supabase as the backend, with phone OTP auth, RLS, RPCs and Realtime. The app shell (#28) is the first code that talks to it: it creates the client at startup, exposes it and the auth session through Riverpod, and guards routes on the session. [0005](0005-dependency-policy.md) asks for an ADR for every new package; 0001 names Supabase but not the client package.

The client must keep the user signed in across launches (persist and restore the session), refresh tokens in the background and when the app resumes, and later serve PostgREST, RPC and Realtime calls.

## Decision
- Use **`supabase_flutter`** (`^2.18.3`), the official Flutter client. It wraps the pure-Dart `supabase` package and adds session persistence (`shared_preferences`), token refresh tied to the app lifecycle, and deep-link handling for auth (`app_links`).
- It is a dependency of **`settlo_core`**, which holds the client and session providers (`supabaseClientProvider`, `sessionProvider`; ADR 0002 puts the Supabase client in core), and of **`app`**, whose `main` calls `Supabase.initialize`. Features read the client through the core providers and do not depend on the package.
- `flutter_riverpod` (approved in 0001) is added to `settlo_core` by the same change, because the providers live there.
- **Provider convention (manager ruling on PR #42).** A provider that takes no parameters, such as `supabaseClientProvider` and `sessionProvider`, is written by hand with `Provider` or `NotifierProvider`. A provider that takes parameters (a family) uses `riverpod_generator` with `@riverpod`. The first issue that needs one adds `riverpod_annotation` and `riverpod_generator`, which 0001 already approves, and runs them through `scripts/codegen.sh`. Hand-written families are a request-changes.
- Settings come from the compile-time environment: `SUPABASE_URL` and `SUPABASE_ANON_KEY`, supplied with `--dart-define-from-file=.env.json`. `app/.env.example.json` is the committed template; `app/.env.json` is gitignored. The key is the anon (publishable) key, which is safe to ship because RLS guards every table. Nothing is hard-coded, and a missing setting stops startup with a message naming the key.

## Alternatives considered
- **The pure-Dart `supabase` package.** Fewer transitive packages, but we would rebuild session storage, lifecycle-aware refresh and auth deep links ourselves. That is security-sensitive code with no product value.
- **Talking to PostgREST and GoTrue over `http` directly.** Even more to rebuild, and it loses Realtime.
- **Secure storage for the session (`flutter_secure_storage`).** It can be plugged in later through `FlutterAuthClientOptions.localStorage` without changing callers. Not taken now so as not to add a second package before there is a threat model for it.

## Consequences
- About 45 packages enter the lockfile, mostly the sub-clients (`gotrue`, `postgrest`, `realtime_client`, `storage_client`, `functions_client`) and the platform-interface splits of `shared_preferences`, `url_launcher`, `app_links` and `path_provider`. The native plugins add a little to app size and to the iOS and Android builds.
- `url_launcher` arrives transitively. When the settle flow needs it directly for `upi://pay` ([0001](0001-stack.md)), that issue still lists it in its own package.
- Tests never initialise Supabase. They override `sessionProvider` (app) or `supabaseClientProvider` with a plain `SupabaseClient` (core), so no test needs a network or a plugin.
