# Release checklist

This document is the release gate owned by Principal QA. Check each item against the release candidate and link the supporting evidence before submission.

## M3 to M4 flatmate gate

- [x] The [real-stack integration test](../app/integration_test/flatmate_flow_test.dart) signs in all three fixed OTP identities, saves each member's name and UPI ID through Profile, and accepts the two invited members through the UI.
- [x] Member 1 creates a three-person flat and records equal, exact and shares expenses, including a one-paisa remainder; every member checks the hand-computed balance and agreed-split fairness view.
- [x] The owing member launches both UPI payments through the simulator's mocked platform channel, explicitly confirms each payment in Settlo, and a server read proves all three balances are zero.
- [x] The iPhone 16 / iOS 18.2 [screen recording](https://github.com/0xPiranhaCodes/settlo/blob/evidence/65-flatmate-gate/flatmate-flow-ios-18.2.mp4?raw=true) covers the passing flow.
- [x] The gate verifies the fixes for [#81](https://github.com/0xPiranhaCodes/settlo/issues/81) and [#82](https://github.com/0xPiranhaCodes/settlo/issues/82) merged in [PR #84](https://github.com/0xPiranhaCodes/settlo/pull/84): Profile saves above the tab bar, and the final settle-up refreshes both space tabs without a manual pull-to-refresh.
- [x] Required hosted CI checks are green for [gate pull request #83](https://github.com/0xPiranhaCodes/settlo/pull/83/checks).

The checked evidence above is bound to issue [#65](https://github.com/0xPiranhaCodes/settlo/issues/65). The gate is not merge-ready until the final hosted checks are green and the merge rule below is satisfied.

## M4 loan-flow gate

- [x] The [real-stack loan integration test](../app/integration_test/loan_flow_test.dart) creates a ₹1,00,000 interest-free monthly loan through the UI, accepts it from the invited number, and records three referenced ₹25,000 repayments.
- [x] The lender reviews every repayment from Activity › Needs you, confirms the first, disputes the second with a reason, and confirms the corrected third; each receipt, progress ring and stat tile is checked against hand-computed integer-paise values.
- [x] A read-only server assertion proves the final `loan_summaries` row is ₹50,000 repaid, ₹50,000 outstanding, two confirmed, one disputed, none pending and on track; Activity contains all seven loan events.
- [x] The iPhone 16 / iOS 18.2 [loan-flow recording](https://github.com/0xPiranhaCodes/settlo/blob/evidence/92-loan-flow/loan-flow-ios-18.2.mp4?raw=true) covers the passing flow.
- [x] The existing flatmate gate passes with both settle-ups confirmed by their payees after recording, with a fresh iPhone 16 / iOS 18.2 [regression recording](https://github.com/0xPiranhaCodes/settlo/blob/evidence/92-loan-flow/flatmate-flow-ios-18.2.mp4?raw=true).
- [x] Required hosted CI checks are green for [loan-flow pull request #102](https://github.com/0xPiranhaCodes/settlo/pull/102/checks).

The evidence above is bound to issue [#92](https://github.com/0xPiranhaCodes/settlo/issues/92). The gate is not merge-ready until the final hosted checks are green and the merge rule below is satisfied.

## Internal builds (TestFlight)

Signing is described in [ADR 0015](adr/0015-ios-release-signing.md), and the test-number sign-in in [the owner decision](decisions/2026-11-10-testflight-test-otp.md). Android (Play internal) is not built yet; it joins the **Release** workflow once a Play Console account and an upload keystore exist.

Both workflows run in the `production` environment and act on `main` only: **Release** fails unless the tagged commit is on `main`, and **Supabase hosted** refuses any other ref. Only admins can create `v*` tags. See [the trust-boundary decision](decisions/2026-11-10-release-trust-boundary.md).

The hosted Supabase project is in Mumbai (AWS ap-south-1); the owner confirmed this on 2026-11-13. The listing's "stored in India" line and the privacy policy (`site/privacy/index.html:118,129`) rely on it.

### Cutting a build

1. Apply migrations to the hosted project: run **Supabase hosted** from `main` with `db-push`, read the dry run, then run it again with **apply** ticked. The first migration push also enables `pg_cron`.

   ```sh
   gh workflow run "Supabase hosted" -f action=db-push
   gh workflow run "Supabase hosted" -f action=db-push -f apply=true
   ```

2. Tag a commit that is on `main` and green there, and push the tag. `v0.1.0-rc1` builds version `0.1.0`; the build number is the workflow's run number.

   ```sh
   git tag v0.1.0-rc1 && git push origin v0.1.0-rc1
   ```

3. **Release** builds against the hosted project, signs, uploads, and waits until App Store Connect reports the build `VALID`. Do not re-run a run that has uploaded; push a new tag.

### Test numbers

The owner keeps the list. To set or change it, store it as a secret and run the workflow; nothing is committed or printed.

```sh
gh secret set HOSTED_TEST_OTP   # paste <number>=<code>,<number>=<code> (country code, no +)
gh workflow run "Supabase hosted" -f action=set-test-otp
```

The numbers lapse 60 days after the last run, and a `supabase config push` removes them; re-run the workflow in either case.

### Production SMS (MSG91)

Real OTPs go out through the `send-sms` hook once the owner's MSG91 account, DLT template and sender id are approved (#119). After the three MSG91 values are stored as **production** environment secrets, run each dispatch from `main` and wait for it to succeed before the next (GitHub keeps only one pending run per concurrency group, so a newer dispatch replaces (cancels) any run still pending):

```sh
gh workflow run "Supabase hosted" -f action=sms-cutover   # deploy, set secrets, enable; stops at the first failure
sleep 5; gh run watch --exit-status "$(gh run list --workflow "Supabase hosted" --limit 1 --json databaseId --jq '.[0].databaseId')"
# Send a real OTP and check it arrives, then keep only the App Review number:
gh secret set HOSTED_TEST_OTP --env production   # paste the single <number>=<code> App Review entry
gh variable set SMS_LIVE --body true
gh workflow run "Supabase hosted" -f action=clear-test-otp   # reduces the list to that entry, then checks it
sleep 5; gh run watch --exit-status "$(gh run list --workflow "Supabase hosted" --limit 1 --json databaseId --jq '.[0].databaseId')"
```

`deploy-send-sms`, `set-sms-secrets` and `enable-sms-hook` run the cutover's steps singly for recovery; run them one at a time in that order, waiting for each with `gh run watch`. `disable-sms-hook` turns the hook off again. Once `SMS_LIVE` is `true`, `clear-test-otp` reduces the hosted test list to the single App Review entry in `HOSTED_TEST_OTP` instead of emptying it, and it and the **Release** workflow (before it builds or uploads) fail unless the hosted list is empty or exactly that entry: any other or extra number fails, and so does an App Review entry that expires within 14 days (`clear-test-otp`, like `set-test-otp`, renews it for 60 days). The comparison runs inside the script and prints neither value. Until then `clear-test-otp` empties the list and both skip the check, so current release candidates keep using test numbers. Set the **production** `HOSTED_TEST_OTP` (it overrides the repository secret in these jobs) to that one entry before setting `SMS_LIVE`, or **Release** fails. Details and rotation: [supabase/README.md](../supabase/README.md#enabling-on-the-hosted-project).

### External TestFlight (Family Testers)

After the workflow PR is reviewed and merged, the manager can run **TestFlight external** (`testflight-external.yml`) from `main`. Select `build_number: 6` for v0.1.0-rc6, `group: Family Testers`, and public `what_to_test` text describing the intended checks. For later candidates, use the actual uploaded build number, which need not match the rc suffix. This workflow configures an existing build; it does not build or upload an IPA, and it does not change the existing Release jobs.

Before running:

- Confirm the iOS build is processed (`VALID`), unexpired, and ready for external review; resolve export compliance in App Store Connect if required.
- Create the named **external** group in App Store Connect and add the intended testers. The workflow fails if the group is missing or internal.
- Use the existing `production` environment App Store Connect secrets (`APP_STORE_CONNECT_API_KEY_P8`, `APP_STORE_CONNECT_KEY_ID`, `APP_STORE_CONNECT_ISSUER_ID`). Store `HOSTED_TEST_OTP` in **production** too, using the same value configured on the hosted project; do not introduce repository-level credentials for this workflow. Its format is `number=code,number=code` (country code without `+`, six-digit code). The first pair becomes the review account; after the SMS cutover it is the only pair. Ensure it is still active on the hosted project.
- Fill in Beta App Review Information's four contact fields in App Store Connect, or provide optional **production** secrets `ASC_REVIEW_CONTACT_FIRST_NAME`, `ASC_REVIEW_CONTACT_LAST_NAME`, `ASC_REVIEW_CONTACT_PHONE`, and `ASC_REVIEW_CONTACT_EMAIL`. Omitted secrets preserve existing fields; incomplete contacts fail before mutations.

The workflow upserts en-US app metadata and What to Test, derives the demo account and review notes at runtime and writes them to Beta App Review Information in App Store Connect, adds group membership if absent, then submits only when review is needed. It masks the number, its sign-in variants and OTP before requests; request/response bodies and credentials are never logged or saved as artifacts. Do not put credentials in workflow inputs. Runs are serialized across all builds because app metadata is shared. App, build validity, external group, complete contacts, review state and group membership are checked before metadata changes. Rejected builds are not resubmitted: resolve the rejection privately in App Store Connect and upload a new build. Expired, processing, export-compliance-blocked and other unsupported states also stop before mutations. Rerun the same inputs after fixing a failure: existing localizations, membership, and pending/approved submissions are reused. HTTP failures omit response bodies; HTTP 409 is explicitly reported as a state/submission conflict and is never automatically retried. Inspect details privately in App Store Connect before rerunning; a conflict after preflight can leave metadata updates applied.

A successful run prints the beta review/external state. `WAITING_FOR_REVIEW` or `IN_REVIEW` is submission evidence, not proof testers can install. After Apple approves, the manager must confirm the build is available to **Family Testers** in App Store Connect, notify testers if needed, and verify installation/sign-in from an external tester's TestFlight account. This PR does not perform that live acceptance step.

Local verification (synthetic in-memory data, no network or production secrets):

```sh
ruby -c scripts/asc-testflight-external.rb
ruby -c scripts/test/asc-testflight-external-test.rb
ruby scripts/test/asc-testflight-external-test.rb
# If installed:
actionlint .github/workflows/testflight-external.yml
```

API references: Apple's [beta app localization attributes](https://developer.apple.com/documentation/appstoreconnectapi/betaapplocalizationupdaterequest/data-data.dictionary/attributes-data.dictionary), [review submissions](https://developer.apple.com/documentation/appstoreconnectapi/get-v1-betaappreviewsubmissions), and [external build states](https://developer.apple.com/documentation/appstoreconnectapi/externalbetastate).

### App Store listing (#266)

The listing copy lives in `docs/store/ios-en-US.json`. The owner approves changes to it before they go live. **App Store listing** (`asc-store-listing.yml`) runs from `main` with the **production** App Store Connect secrets. With `dry_run` (the default), it prints a live-vs-proposed diff for each field and changes nothing. A real run writes only the changed fields:

- the en-US app info: name, subtitle and privacy URL;
- the editable iOS version: description, keywords, promotional text, support URL, marketing URL and copyright;
- the primary and secondary categories.

The name is written first and on its own. If no version is editable, the run fails. A real run creates a version only when `create_version` is set, and it logs that it did. If Apple then rejects the name, the run stops and says what it wrote: the new version, if it created one, and nothing else. The copyright holder is the single `copyright` field in the listing JSON. App Privacy answers and the age rating are entered by hand from `docs/store/privacy-labels.md`.

```sh
ruby scripts/asc-store-listing.rb --check
ruby scripts/test/asc-store-listing-test.rb
```

**Expire TestFlight builds** (`asc-expire-builds.yml`) expires every processed, unexpired iOS build except the build numbers in `keep_versions` (for example `12`). Builds that are still processing are skipped. The run fails without changes if a kept number does not exist. `dry_run` defaults to true and prints the plan. Test locally with `ruby scripts/test/asc-expire-builds-test.rb`.

### First TestFlight checklist

- [ ] A fresh install from TestFlight signs in with a test number against the hosted project.
- [ ] The flatmate flow works end to end between two testers: invite, expense, settle-up, confirm.
- [ ] On a real iPhone (iOS 16.2+), a pending settle-up shows the Live Activity on the lock screen and in the Dynamic Island, with "A flatmate" in place of any number (#105).
- [ ] **Confirm** in the expanded island opens the confirm sheet.
- [ ] The activity ends on confirm, on dispute and on sign-out.

## M6 Release gate

- [ ] Only the App Review test number remains on the hosted project (owner decision, 11 Nov 2026): `HOSTED_TEST_OTP` holds that single `number=code` entry, the repository variable `SMS_LIVE` is `true`, and **Supabase hosted** has run with `clear-test-otp`, so **Release** fails if any other number comes back (#119).
- [ ] Store listings are complete for iOS and Android.
- [ ] App Store and Play Store privacy labels match the app's actual data collection and use.
- [ ] Final release screenshots are approved, including the 390x844 and 360x800 layouts.
- [ ] The release candidate has completed beta testing.
- [ ] The light-first user test is complete and its findings are resolved or explicitly accepted.
- [ ] Required CI checks are green for the release candidate.
- [ ] Production SMS OTP is live: the owner's MSG91 account, DLT template and sender id are approved; **Supabase hosted** has run `deploy-send-sms`, `set-sms-secrets` and `enable-sms-hook` ([steps](../supabase/README.md#enabling-on-the-hosted-project)). An OTP to a real number arrives, and `supabase config diff` shows no `hook` changes.
- [ ] After `supabase config push`, the hosted Auth settings show the SMS OTP expiry is `600` seconds (10 minutes).
- [ ] The iOS and Android store submissions have been made.

The M6 gate is complete when both stores have accepted a submission for review.

## Merge rule

All changes are squash-merged only after the hosted `Analyze & test`, `Android
debug build`, `iOS debug build`, and `Supabase` checks are successful and the
pull request has one approval from a non-author agent. The iOS job reports a
successful skipped status when a pull request changes no iOS-relevant paths;
pushes to `main` always build iOS. Direct pushes to `main` are not allowed.

`scripts/ci-local.sh` is an optional developer preflight, not merge evidence or
a substitute for hosted CI. Inspect and trust a branch before running it because
the script executes project-controlled build and package logic on the host.

## Coverage baseline updates

The committed total line-coverage baseline is a hand-maintained ratchet. After a green `Analyze & test` run on `main` reports total line coverage above `.github/coverage-baseline.txt`, open a pull request that updates the file to the run's two-decimal `Total line coverage` value and link that run as evidence. Never lower the baseline; a legitimate exception needs an explicit manager ruling in the pull request. The workflow reads the baseline from `main` when checking pull requests, and independently requires at least 80% line coverage for `packages/core/lib/money`.

## UI comparison evidence

Every UI pull request must attach an app-vs-canvas comparison at 390x844 in
every affected theme. Use the committed canvas render from
`design/reference/390/` on the left and the matching app golden on the right.
Label each pair with the screen, theme, and commit SHA so a reviewer can trace
the evidence.

At 360x800, the fixed 390px canvas would only produce a crop, so there is no
canvas pixel reference. Attach the app screenshot and state that the compact
layout has no overflow, no clipping, and preserves the same content hierarchy
as the 390 artboard. Flutter reports `RenderFlex` and other overflow errors to
the widget-test binding, which fails the test. Tests must not consume or ignore
those failures with `tester.takeException()`. The committed 360 app golden
continues to guard the accepted compact layout against regression.

Regenerate canvas references with `scripts/render-canvas.sh` only when the
corresponding `design/canvas/*.dc.html` source changes. If a deliberate app
deviation remains, call it out below the comparison, explain why, and obtain
design-owner approval; anti-aliasing or platform-metric differences must not be
used to excuse layout, spacing, colour, or typography mismatches.

## Regenerating app and core goldens

The canonical app and `packages/core` goldens are generated by the hosted `CI`
workflow's `Regenerate app and core goldens` job on `ubuntu-24.04` with the
repository's pinned Flutter version. From GitHub Actions, choose **CI**, select
**Run workflow**, enable **Regenerate app and core goldens instead of running
CI**, and run the branch. Equivalently:

```sh
gh workflow run CI --ref <branch> -f update_goldens=true
```

The job commits changed PNGs directly to the selected branch as
`github-actions[bot]`. Because a push made with `GITHUB_TOKEN` does not trigger
the normal CI workflow, review the bot commit and manually run **CI** again with
the golden-regeneration option disabled. That second hosted run must compare
every app and core golden on Linux before merge. `scripts/ci-local.sh
--update-goldens` remains an optional container-based developer preflight.
Local macOS tests can report expected glyph-rasterization differences, so do not
update goldens on macOS or treat those platform-only diffs as canonical.
