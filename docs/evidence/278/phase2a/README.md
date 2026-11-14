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
glass rendering or UIKit touch behavior. The native delete-account alert
uses the test system-font fallback in the Linux renderer in both before and
after images; those captures document modal structure, not readable native
text rendering. Behavioral tests assert its real confirmation labels.

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

The full serial Docker suite passes **1935 tests**, including all **48 profile
package tests**. Merged coverage is **98.26% (6114/6222)**, above main's **98.11%**
baseline; money coverage is **100.00% (110/110)**. The focused app suites pass **160 tests**, and the focused core suite passes
**16 tests**.
Host native export/share checks pass **7 tests**.

The owner corrections are included: Loan uses the counterparty name and initial,
its download action is beside Close, and task headers omit avatars and marks.
Profile task completion returns results through the owning sheet; irreversible
iOS account deletion retains its native alert. Appearance failures remain inline.

See [validation.txt](validation.txt), [full test output](full-tests.log), and
[LCOV](lcov.info). [The original profile failures](profile-test-failures.log)
are retained as historical evidence.

[Golden file manifest](golden-files.txt) lists the 400 golden files touched by
this PR relative to its main base. If Phase 2b merges first, rebase and regenerate
the overlapping sheet backdrops before merging this PR.

## Review correction

The expense accessory now hugs its widest line and keeps the amount and share
end-aligned. The share wraps within 45% of the row at large text sizes; it is
never ellipsized. The title takes the remaining space and may ellipsize.
Rows without a share retain their existing layout.

The four new regression cases cover a short amount and a longer share at
320pt and 375pt, at 100% and 200% text. They assert the complete paragraph,
width limit, common right edge, and separation from the leading title.

The 24 expense captures in `review-before/` are from reviewed head `e845714`,
not the Phase 1 baseline used by `before/`. `review-expenses-01.jpg` through
`review-expenses-12.jpg` pair them with the corrected `after/` images.
Only 30 golden PNGs changed: 24 with expense rows and six with the unified
“Not received” copy. Every changed image was visually inspected; matching
`after/` captures and the two affected Phase 2a contact sheets were refreshed.

Sheet page duplication, the unused navigator drag-handle option and frame
inset, repeated title measurement, and stale loan route comments were removed.
Sheet scope callbacks now use stable State methods.

The initial full app pass found four additional stale liquid-glass space
snapshots (1144 passed, 4 failed). Those snapshots were refreshed and visually
checked before the final serial rerun; the diagnostic output is retained in
`review-initial-full-tests.log`.
