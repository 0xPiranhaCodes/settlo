# Settlo app

## Local CI

Hosted GitHub Actions are manual-only while the private repository has no
Actions budget. Run the complete release gates from the repository root:

```sh
scripts/ci-local.sh
```

The script analyzes the workspace, runs every test with the coverage floors,
compares app and core goldens in a pinned Linux/amd64 Flutter container, tests
the local Supabase stack, and builds the Android and iOS debug apps. Android is
reported as skipped only when the local SDK or command-line tools are missing.
The pull request reviewer must paste the passing summary and commit SHA into
their approval. See [the decision](../docs/decisions/2026-11-09-local-ci.md).

## Supabase settings

The app reads `SUPABASE_URL` and `SUPABASE_ANON_KEY` at compile time
(ADR [0007](../docs/adr/0007-supabase-flutter.md)) and refuses to start without
them. Copy the template, fill it in, and pass it to every `flutter run` or
`flutter build`:

```sh
cp .env.example.json .env.json   # gitignored
flutter run --dart-define-from-file=.env.json
```

For local development, start this worktree's Supabase stack from the repo root
and copy the values it prints:

```sh
scripts/supabase-local.sh start
scripts/supabase-local.sh status
```

- `SUPABASE_URL`: the API URL. Each worktree gets its own port, so the
  template's port is only an example.
- `SUPABASE_ANON_KEY`: the anon key (the CLI may label it the publishable key).

On the Android emulator, replace `127.0.0.1` with `10.0.2.2`. Sign in with the
test numbers in `supabase/config.local-dev.toml`.

## Web preview (development only)

`web/` exists so the owner and reviewers can preview the app in Chrome. Web is
not a shipped platform: Settlo ships on iOS and Android only (ADR
[0001](../docs/adr/0001-stack.md)), CI does not build or test web, and
platform features (Live Activities, widgets, contacts, UPI intents) do not
work there.

Against the local stack, using this worktree's values from
`scripts/supabase-local.sh status` in `.env.json` as above (`127.0.0.1` works
in Chrome; the local API allows browser origins):

```sh
flutter run -d chrome --dart-define-from-file=.env.json
```

To check that the bundle compiles without a stack, build it with the template:

```sh
flutter build web --dart-define-from-file=.env.example.json
```

Sign in with the test numbers in `supabase/config.local-dev.toml`; no SMS is
sent locally.

## Integration test

`integration_test/` signs in end to end against this worktree's local stack
with the test number +91 90000 00001 and code 123456 (fixed in
`supabase/config.local-dev.toml`, so no SMS is sent). It needs a running
stack, `.env.json` filled in as above, and an iOS simulator or Android
emulator:

```sh
scripts/supabase-local.sh start            # from the repo root
cd app
flutter devices                            # pick a simulator or emulator id
flutter test integration_test --dart-define-from-file=.env.json -d <device-id>
```

On the Android emulator, use `10.0.2.2` instead of `127.0.0.1` in
`.env.json`. CI does not run this yet (no device; ADR
[0008](../docs/adr/0008-integration-test.md)); `flutter test` without a path
runs `test/` only.
