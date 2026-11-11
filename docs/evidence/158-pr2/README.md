# #158 PR 2 evidence: iOS controls and lists

**After** images and the recording come from a fresh iPhone 17 Pro simulator
on iOS 26.1 (created for this run and deleted afterwards), in dark theme, at
this PR's code. They show the real screens and production routes on the
fakes from `app/test/support`, driven by a throwaway integration test (not
committed); `xcrun simctl io` captured each frame. **Before** images are the
phase 1 audit's, from `docs/design/158/before/` (iPhone 16 Pro, iOS 26.1,
base `07e7eff`). All images are 603×1311.

| Before | After | What changed |
| --- | --- | --- |
| `before-02-phone.png` | `after-02-phone.png` | The standard back chevron replaces the round back button (A2). |
| `before-04-otp.png` | `after-04-otp.png` | The same on the code step (A4). |
| `before-03-sheet-country-picker.png` | `after-03-country-picker.png`, `after-03b-country-search.png` | A page sheet with Cancel, a search field and an inset-grouped list; the choice is a trailing checkmark, not "Selected" (A3). |
| `before-20-spaces.png` | `after-20-spaces.png`, `after-20b-spaces-search.png` | Search under the large title; + is a plain bar button (C1). |
| `before-21-sheet-create-space.png` | `after-21-create-space.png` | A page sheet with Cancel and Create in the bar (Create turns gold once there is a name), and the sliding segmented control (C3). |
| `before-30-add-expense.png` | `after-30-add-expense.png`, `after-30b-date-picker.png` | Trailing checkmarks for the split, the sliding segmented control, and the date as a Cupertino wheel with Done (D2–D4). |
| `before-44-new-loan.png` | `after-44-new-loan.png`, `after-44b-due-day-picker.png` | I lent / I borrowed as a sliding control, the due day as a wheel, interest as a Cupertino switch that is never green (E5). |
| `before-50-activity.png` | `after-50-activity.png` | Search under the title (F1). |
| — | `after-notice-banner.png` | A notice drops from the top instead of a snackbar (X8). |

`search-and-pickers.mp4` (402 px wide, H.264): typing "goa" filters Spaces;
Add expense opens, the date wheel turns and Done sets it, the split mode
slides; New loan switches direction, then the due-day wheel turns and Done
sets it.

Not shown on the simulator, covered by widget tests instead:

- Activity's pinned day headings: the fixture feed is too short to scroll
  them under the bar. `app/test/ios_controls_test.dart` checks they are
  `PinnedHeaderSliver`s on iOS and absent on Android.
- The keyboard Done bar (D5): the simulator uses its hardware keyboard, so
  no software keyboard appears. `packages/core/test/widgets/ios_controls_test.dart`
  checks that Done closes the keypad on iOS and is absent on Android.
- The discard prompts for Create space, Edit expense and Record repayment,
  and Export's row indicator (G6).

Android keeps its Material controls: each control's Android path is tested,
and the Ubuntu golden regeneration changed no existing (Android) golden; it
only added the `*_ios_*` goldens.
