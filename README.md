# Settlo

Settlo helps people in India split expenses with flatmates and track money lent to friends. Create shared spaces, record expenses and loans, and keep balances together. To settle up, Settlo opens your UPI app with the payment details filled in; you approve the payment there, record it in Settlo, and the other person confirms. Settlo never moves money or automatically verifies payments.

[Website](https://settlo.hellojosh.studio/) · [Privacy](https://settlo.hellojosh.studio/privacy/) · [Support](https://settlo.hellojosh.studio/support/)

**Availability:** iPhone TestFlight beta; see the [website for beta access](https://settlo.hellojosh.studio/). Android is planned for later. There is no public App Store or Google Play release yet.

## Stack and layout

Flutter/Dart app with Supabase Auth, Postgres and Edge Functions; Riverpod for state and Drift for local storage.

| Directory | Contents |
| --- | --- |
| `app/` | Flutter app, platform projects and integration tests |
| `packages/` | Shared UI, local storage, platform bridges and feature packages |
| `supabase/` | Database migrations, tests and Edge Functions |
| `site/` | Public website, privacy and support pages |
| `scripts/` | Development, testing, release and site tooling |
| `docs/` | Architecture, API, design and release documentation |

## Local setup

Install Flutter **3.47.9** (pinned in [.fvmrc](.fvmrc), includes Dart), the Supabase CLI and Docker with its daemon running. For the app, have an iOS simulator with Xcode on macOS or an Android emulator with the Android SDK configured.

From the repository root:

```sh
flutter pub get
scripts/supabase-local.sh start
scripts/supabase-local.sh status
cp app/.env.example.json app/.env.json
```

Fill the gitignored `app/.env.json` with `SUPABASE_URL` and `SUPABASE_ANON_KEY` from the local status output (API URL and anon/publishable key). Ports vary by worktree. On the Android emulator, replace `127.0.0.1` in the URL with `10.0.2.2`. Then, with the simulator or emulator running:

```sh
cd app
flutter run --dart-define-from-file=.env.json
```

See [app setup](app/README.md) for local sign-in and integration testing. The web target is a development preview only. Always use the [local Supabase wrapper](supabase/README.md#local-development), which keeps each worktree's stack separate. From the repository root, stop it with:

```sh
scripts/supabase-local.sh stop
```

## Checks

From the repository root:

```sh
flutter analyze
scripts/supabase-local.sh test db  # requires the local stack above
```

The optional full preflight is `scripts/ci-local.sh`: it runs workspace tests and Linux goldens, database and Edge Function checks, and platform builds. It additionally needs Python 3 and Deno, Docker support for Linux/amd64, and the platform build tools; see the [script](scripts/ci-local.sh) for details. Hosted CI remains the merge gate; local macOS golden rendering is not the reference.

## Documentation and automation

- [Release checklist](docs/release.md), [brand](docs/brand.md), [API](docs/api.md)
- [Architecture decisions](docs/adr/README.md) and [project decisions](docs/decisions/)
- Workflows: [CI](https://github.com/0xPiranhaCodes/settlo/actions/workflows/ci.yml), [Pages](https://github.com/0xPiranhaCodes/settlo/actions/workflows/pages.yml), [Release](https://github.com/0xPiranhaCodes/settlo/actions/workflows/release.yml)

## Licence

This repository does not currently include a project licence. No open-source licence is granted for the project; third-party assets retain their own licences.
