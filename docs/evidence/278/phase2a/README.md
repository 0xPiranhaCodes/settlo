# Phase 2a sheet chrome evidence

The comparison uses the Phase 1 starting revision `577a979` as **before**. The
`phase2a_*.png` files capture the same fake account, dates, routes, and actions
in both revisions using the pinned Linux Flutter renderer
`settlo/flutter-goldens:3.47.9-amd64`.

The matrix covers loan detail, profile, new expense, settle up, payment, new
loan, confirm repayment, create space, members, resend invite, export,
appearance, and delete account. Each has light and dark captures at 390×844,
375×667, and 375×667 with 200% text. The test uses the iOS sheet presentation;
native platform views are mocked, so these images do not establish native
glass rendering or UIKit touch behavior. The old native delete-account alert
uses a system-font fallback in the Linux renderer; its before image documents
modal structure, not native text rendering.

`app/test/phase2a_sheet_golden_test.dart` reproduces the 78-case matrix.
`app/test/phase2a_repayment_actions_test.dart` adds four scrolled SE captures
at 100%/200% text, checking the painted pill widths as well as touch targets.

| Size | Light | Dark |
| --- | --- | --- |
| 390×844 | [Contact sheet](contact-390x844-light.jpg) | [Contact sheet](contact-390x844-dark.jpg) |
| SE 375×667 | [Contact sheet](contact-se375x667-light.jpg) | [Contact sheet](contact-se375x667-dark.jpg) |
| SE 200% text | [Contact sheet](contact-se375x667_text200-light.jpg) | [Contact sheet](contact-se375x667_text200-dark.jpg) |

[Repayment action comparison](contact-actions.jpg). Existing feature
golden tests additionally cover content states and Android presentation.

The core behavioral tests exercise instant reduced-motion presentation and
dismissal on both platforms, nested navigation within a single sheet, live
Reduce Transparency changes, and short-amount row layout. App tests exercise
root-sheet tab isolation, return to the originating tab, dirty-form dismissal,
confirmation races, and equal-width repayment actions with complete labels at
200% text.

The PR is **not merge-ready**: the Docker suite has 1,915 passes and 12
failures in the profile package. Merged coverage is **97.73% (6072/6213)**,
below main's **98.11%** baseline. Remaining work is to resolve those profile
tests and restore the coverage gate.

See [validation.txt](validation.txt) for package totals,
[profile failure output](profile-test-failures.log), and [LCOV](lcov.info).
