# Release checklist

This document is the release gate owned by Principal QA. Check each item against the release candidate and link the supporting evidence before submission.

## M6 Release gate

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

All changes are squash-merged only after a non-author reviewer runs
`scripts/ci-local.sh` on the pull request head and includes its passing summary
and commit SHA in an approval. Direct pushes to `main` are not allowed. Hosted
GitHub Actions are manual-only while the repository has no Actions budget; see
[the local-CI decision](decisions/2026-11-09-local-ci.md).

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

The canonical app and `packages/core` goldens are generated in the pinned
Linux/amd64 Flutter container used by the local CI script. From the repository
root, run:

```sh
scripts/ci-local.sh --update-goldens
```

This first compares every app golden, then regenerates only the core goldens and
runs the complete local CI suite, including a final Linux comparison. Review and
commit the changed PNGs, then rerun `scripts/ci-local.sh` so its summary names
the final commit. Local macOS tests still compare every app and core golden, so
they can report expected glyph-rasterization differences. Do not update goldens
on macOS or treat those platform-only diffs as canonical.
