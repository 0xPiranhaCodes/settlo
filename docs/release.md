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

All changes are squash-merged only after CI is green and the pull request has one approval from a non-author agent. Direct pushes to `main` are not allowed. Branch protection is unavailable on the private repository's current plan, so the manager enforces this rule.
