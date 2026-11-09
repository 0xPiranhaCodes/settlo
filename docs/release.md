# Release checklist

This document is the release gate owned by Principal QA. Check each item against the release candidate and link the supporting evidence before submission.

## M6 Release gate

- [ ] Store listings are complete for iOS and Android.
- [ ] App Store and Play Store privacy labels match the app's actual data collection and use.
- [ ] Final release screenshots are approved, including the 390x844 and 360x800 layouts.
- [ ] The release candidate has completed beta testing.
- [ ] The light-first user test is complete and its findings are resolved or explicitly accepted.
- [ ] Required CI checks are green for the release candidate.
- [ ] The iOS and Android store submissions have been made.

The M6 gate is complete when both stores have accepted a submission for review.

## Merge rule

All changes are squash-merged only after the `Analyze & test`, `Android debug build`, `iOS debug build`, and `Supabase` checks are green and the pull request has one approval from a non-author agent. Direct pushes to `main` are not allowed. Branch protection is unavailable on the private repository's current plan, so the manager enforces this rule.

## Coverage baseline updates

The committed total line-coverage baseline is a hand-maintained ratchet. After a green `Analyze & test` run on `main` reports total line coverage above `.github/coverage-baseline.txt`, open a pull request that updates the file to the run's two-decimal `Total line coverage` value and link that run as evidence. Never lower the baseline; a legitimate exception needs an explicit manager ruling in the pull request. The workflow reads the baseline from `main` when checking pull requests, and independently requires at least 80% line coverage for `packages/core/lib/money`.

## UI comparison evidence

Every UI pull request must attach app-vs-canvas comparisons for both required
viewports, 390x844 and 360x800, in every affected theme. Use the committed
canvas render from `design/reference/390/` or `design/reference/360/` on the
left and the matching app golden on the right. Label each pair with the screen,
viewport, theme, and commit SHA so a reviewer can trace the evidence.

Regenerate canvas references with `scripts/render-canvas.sh` only when the
corresponding `design/canvas/*.dc.html` source changes. If a deliberate app
deviation remains, call it out below the comparison, explain why, and obtain
design-owner approval; anti-aliasing or platform-metric differences must not be
used to excuse layout, spacing, colour, or typography mismatches.
