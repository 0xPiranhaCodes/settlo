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

Signing is described in [ADR 0015](adr/0015-ios-release-signing.md), and the test-number sign-in in [the owner decision](decisions/2026-11-10-testflight-test-otp.md). Android (Play internal) is a stub job in the same workflow until a Play Console account exists.

### Cutting a build

1. Apply migrations to the hosted project: run **Supabase hosted** with `db-push`, read the dry run, then run it again with **apply** ticked. The first migration push also enables `pg_cron`.

   ```sh
   gh workflow run "Supabase hosted" -f action=db-push
   gh workflow run "Supabase hosted" -f action=db-push -f apply=true
   ```

2. Tag a commit that is green on `main` and push the tag. `v0.1.0-rc1` builds version `0.1.0`; the build number is the workflow's run number.

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

### First TestFlight checklist

- [ ] A fresh install from TestFlight signs in with a test number against the hosted project.
- [ ] The flatmate flow works end to end between two testers: invite, expense, settle-up, confirm.
- [ ] On a real iPhone (iOS 16.2+), a pending settle-up shows the Live Activity on the lock screen and in the Dynamic Island, with "A flatmate" in place of any number (#105).
- [ ] **Confirm** in the expanded island opens the confirm sheet.
- [ ] The activity ends on confirm, on dispute and on sign-out.

## M6 Release gate

- [ ] The test OTP numbers are gone from the hosted project: **Supabase hosted** has run with `clear-test-otp`, and the `HOSTED_TEST_OTP` secret is deleted (#119).
- [ ] Store listings are complete for iOS and Android.
- [ ] App Store and Play Store privacy labels match the app's actual data collection and use.
- [ ] Final release screenshots are approved, including the 390x844 and 360x800 layouts.
- [ ] The release candidate has completed beta testing.
- [ ] The light-first user test is complete and its findings are resolved or explicitly accepted.
- [ ] Required CI checks are green for the release candidate.
- [ ] Production SMS OTP is live: the owner's MSG91 account, DLT template and sender id are approved; `send-sms` is deployed, its secrets are set, and the Send-SMS hook is enabled in the Dashboard ([steps](../supabase/README.md#enabling-on-the-hosted-project)). An OTP to a real number arrives, and `supabase config diff` shows no `hook` changes.
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
