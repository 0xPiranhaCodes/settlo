# Issue 278 — Phase 2b tab chrome

The four tabs share a 34pt bold large title, a 17pt semibold collapsed title,
16pt content/action insets, and a flat header that gains 80% background fill
and sigma-30 blur only when content passes underneath. Routine native glass
actions use primary-text colour. The native tab bar implementation is unchanged.

Home uses a plain overview group with one main amount, one context line and
three stats. Tab lists use inset groups and shared rows; leading graphics scale
with text to 150%, without scaling avatar lettering twice. Activity uses the
Cupertino sliding segmented control and retains pinned date headings on iOS.
Space-scoped Activity retains its existing sheet presentation.

## Review fixes

Spaces and Loans draw each inter-item hairline after the row's footer. Home
loans use the same 16pt side/bottom progress inset as Loans, with hairlines
between items. Pending repayment detail keeps its semantic colour. Home's
activity header uses SEE ALL, and the tab capture fixtures all use Sana's initial.
The scoped Activity copies identify Phase 2a (#283) as their removal point.

Review items 4 (Activity emphasis, pending and action cues), 6 (segmented
filter overflow), and 7 (row reflow measurement cost) remain Phase 3 follow-ups.

## Captures

`before/` and `after/` contain the same fixture data for Home, Spaces, Loans and
Activity, in light and dark at 390×844, 375×667, and 375×667 at 200% text.
The before revision is `94d56e9` (`origin/main` when the branch was created).
The capture test is `app/test/tab_chrome_golden_test.dart`.

These are deterministic Flutter widget goldens with `TargetPlatform.iOS` set
explicitly, including the iOS search fields. The native UIKit tab bar does not render in widget goldens; its platform
channel is mocked and its bottom inset is retained. Existing tab goldens also
cover the unchanged Flutter fallback bar. Native glass foreground arguments and the unchanged iOS navigation
paths are tested separately. This evidence does not claim a new simulator or
VoiceOver walkthrough.

## Validation

The Linux suite runs one test process at a time in
`settlo/flutter-goldens:3.47.9-amd64`. `verify-linux.sh` records the package loop
and LCOV merge. The export-isolate test and platform file-sharing tests run on
macOS; their normalized traces are included in the merged coverage result.

The shared scaffold test sweeps every scroll point from 1 through 90 at 100%
and 200% text for all four titles on iOS and Android. It checks title glyphs
against action bounds and header clipping, and taps the action at each point.
The matrix also asserts that the actual first group/filter begins exactly 16pt
below the shared header. Existing complete-text tests cover long phone-number
rows at 360pt, 375pt and 390pt widths.

Dependent sheet screenshots include the newly rendered parent tab. The pixel
change bounds are recorded in `sheet-background-diffs.json`; the sheets' own
content and implementations are unchanged. All matrix pairs and changed
existing captures were visually inspected.

The full serial Linux run passed **1,768 tests**: app 996, core 516,
local 75, platform 73, auth 60, and profile 48. The native complement adds
one large-export test and six file-sharing tests: **1,775 distinct tests**.
The six new core chrome checks also passed natively (already counted in Linux).

Merged line coverage is **98.32% (6,162 / 6,267)** against the main baseline
of **98.11%**. Money coverage is **100% (110 / 110)**. See `linux-tests.log`,
`validation.json`, and the normalized native LCOV inputs.

The review-fix capture pass passed 80 selected tests; its progress is in `captures.log`. The
baseline capture pass passed 24 tests. A 14-pixel dependent change at the top-right
corner of the 200% dark Create space sheet is retained; its content is unchanged.
A filtered-capture missing-logo artifact was discarded, and the normal-order
full run verifies the original sheet-content baseline. The focused Linux pass passed 269 tests
(263 app checks including the 24 tab goldens, plus 6 core chrome checks);
the native focused pass passed 245. See `focused-linux.log`,
`native-focused.log`, and `native-tab-chrome.log`. `flutter analyze` is clean, host
`flutter pub get` is restored, and `pubspec.lock` is unchanged.

The Docker container ran only after the parallel Phase 2a container exited;
all packages and test files ran with concurrency 1. The two platform-dependent
test files were excluded from Linux and run on macOS as described above.
