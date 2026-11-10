# 0014 iOS release signing: cloud-managed, through the App Store Connect API key

## Status
Proposed (10 Nov 2026), with #110.

## Context
Issue #110 asks for TestFlight uploads from a tagged workflow, signed through an App Store Connect API key held in CI secrets. The Runner embeds the `SettloWidgets` extension ([0013](0013-live-activity-and-ongoing-notification.md)), so two identifiers need distribution profiles: `app.settlo` and `app.settlo.SettloWidgets`. Neither target has an entitlements file. GitHub's macOS runners start with an empty keychain on every run.

## Decision
- **Unsigned archive, cloud-signed export.** `.github/workflows/release.yml` runs `flutter build ipa --no-codesign`, then one `xcodebuild -exportArchive -allowProvisioningUpdates` with `-authenticationKeyPath`, `-authenticationKeyID` and `-authenticationKeyIssuerID`. The export options ask for `signingStyle = automatic`, `method = app-store-connect` and `destination = upload`. Xcode signs with Apple's cloud-managed distribution certificate, creates or refreshes both profiles, and uploads the build. No certificate, private key or profile is stored in the repository, in secrets or on the runner.
- **Secrets**: `APP_STORE_CONNECT_API_KEY_P8`, `APP_STORE_CONNECT_KEY_ID`, `APP_STORE_CONNECT_ISSUER_ID` and `APPLE_TEAM_ID`. The key is written to the runner's temp directory for the one step that needs it and removed afterwards. The key needs the Admin role, because cloud-managed signing requires it.
- **Version and build number**: the tag gives the version (`v0.1.0-rc1` → `0.1.0`), and the workflow's run number gives the build number, so it only goes up. `manageAppVersionAndBuildNumber` is off, so App Store Connect never renumbers a build.
- **Hosted config**: the workflow writes a dart-define file from the repository variables `SUPABASE_URL` and `SUPABASE_PUBLISHABLE_KEY` (as `SUPABASE_ANON_KEY`, the name [0007](0007-supabase-flutter.md) reads). Nothing hosted is committed.
- **Proof of upload**: `scripts/asc-wait-for-build.rb` asks the App Store Connect API for the build number and waits until it is `VALID`. It runs on Ubuntu with Ruby's standard library, so the wait costs no macOS minutes.
- **Export compliance**: `ITSAppUsesNonExemptEncryption = false` in the Runner's Info.plist. Settlo uses only the operating system's HTTPS, which is exempt. Without the key, every build waits in TestFlight for a manual answer.

## Alternatives considered
- **Signed archive with `-allowProvisioningUpdates`.** Archiving wants a development certificate. On an empty keychain Xcode creates a new one on every run, until the team reaches Apple's certificate limit.
- **fastlane (`match`, or `cert` and `sigh`).** `match` needs a private certificate repository and a passphrase. `cert` creates a distribution certificate per clean machine and reaches the same limit. Either adds a Ruby toolchain for what one `xcodebuild` call does.
- **A distribution `.p12` and profiles in secrets.** It works, and it means renewing them by hand every year and updating the profiles whenever a capability changes.

## Consequences
- An unsigned archive carries no entitlements. That is fine today. When a target gains an entitlements file (Universal Links, push, an App Group), the archive step must sign, and this ADR needs revisiting.
- Re-running a release run that has already uploaded fails, because the build number is already taken. Push a new tag.
- The release workflow does not run tests. Tag only commits that are green on `main`.
- Android (Play internal) is a stub job behind the `android` input until a Play Console account and an upload keystore exist.
