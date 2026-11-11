# #158 PR 1 evidence: iOS sheets, nav bar and confirmations

**After** images and recordings come from an iPhone 17 Pro simulator on iOS
26.1, in dark theme, at this PR's head. They show the real `SettloApp` with
the production router and shell, on the fakes from `app/test/support`. A
throwaway integration test (not committed) drove the app, and
`xcrun simctl io` captured each frame. **Before** images are the phase 1
audit's, from `docs/design/158/before/`: an iPhone 16 Pro on iOS 26.1, at
base `07e7eff`, with the same 402×874 pt canvas. All images are 603×1311.

| Before | After | What changed |
| --- | --- | --- |
| `before-30-add-expense.png` | `after-30-add-expense.png` | Add expense is a `CupertinoSheetRoute`. It slides up over a stacked card instead of pushing in from the right. |
| `before-31-settle-request.png` | `after-31-settle-request.png` | Settle up is a native sheet, too. |
| `before-44-new-loan.png` | `after-44-new-loan.png` | New loan is a native sheet, too. |
| `before-22-space-expenses.png` | `after-22-space-expenses.png` | The space has a native large-title bar: the standard back chevron says "Spaces", and the circular back button is gone. |
| `before-23-space-expenses-scrolled.png` | `after-23-space-expenses-scrolled.png` | Scrolling collapses the large title into the translucent inline bar. |
| `before-26-sheet-edit-expense.png` | `after-26-delete-expense.png` | Delete expense asks with a `CupertinoActionSheet` instead of "Tap again to delete". |
| `before-17-sheet-sign-out.png` | `after-17-sign-out.png` | Signing out with unsent changes asks with an action sheet: "Sign Out Anyway" in system red, then Keep. |
| `before-18-sheet-delete-account.png` | `after-18-delete-account.png` | Delete account asks with a `CupertinoAlertDialog`. Its non-destructive button is primary text, never system blue. |

Recordings (402 px wide, H.264):

- `sheet-open-drag-dismiss.mp4`: from Flat 402, Add expense slides up and the
  space scales back behind it. A drag down from the sheet's title dismisses it.
- `swipe-back.mp4`: an edge swipe from Flat 402 returns to Spaces.
  `after-swipe-back-lands-on-spaces.png` is the frame after the swipe. Before
  this PR, the swipe did nothing on these routes (see the audit's "PR 1 as
  built").
- `discard-prompt.mp4`: Add expense with ₹1,234 and "Weekly groceries"
  entered. A drag down from the title snaps back and asks "Discard
  changes?" (`after-discard-prompt.png`). Keep editing keeps both values; a
  second drag and Discard closes the sheet once, back to Flat 402. Captured
  after the review fixes, merged with `main` (#160 native tab bar), on a
  fresh iPhone 17 Pro iOS 26.1 simulator that was deleted afterwards.

A clean sheet still drags away without asking, and a sheet that is saving
stays put. Close asks the same way. Add expense, Settle up (back from the
UPI app, not yet recorded), New loan and Confirm settlement (a dispute
reason typed) count as dirty. Under Reduce Motion, action sheets and alerts
now appear in place instead of sliding or scaling.

Android keeps its current behaviour. Every change sits behind an iOS
platform check, and `app/test/ios_navigation_test.dart` checks each task
route on both platforms. Only the new iOS goldens
(`spaces_expenses_ios_*`) are added. The existing goldens render on the
default test platform and do not change.
