# Issue 158: iOS Human Interface Guidelines audit

Phase 1 of #158: an audit only, with no app code changed. The manager has
approved it and answered the open questions (see the end of this document and
[docs/decisions/2026-11-11-ios-hig.md](../../decisions/2026-11-11-ios-hig.md)).
PR 1 is implemented in the same PR as this audit.

**Goal.** On iOS, Settlo should feel like one of Apple's own apps. It keeps the
Settlo colour tokens, the S mark and Figtree (docs/context-pack.md, docs/brand.md).
Android keeps Material behaviour where the two platforms differ.

**Evidence.** The screenshots in `before/` come from the iOS 26.1 simulator on an
iPhone 16 Pro, in dark theme, at base commit `07e7eff`. They show the real app:
`SettloApp`, the production router, `SettloPage` and the shell. The repositories
are the fakes from `app/test/support` and were driven by a throwaway integration
test that is not committed. The images are downscaled to 603×1311. The software
keyboard is hidden because the simulator uses its hardware keyboard. The
empty-space state is not in the set because the shared fixture has no route to
it; `app/test/goldens/spaces_empty_*` covers it.

**References.** HIG means the Apple Human Interface Guidelines at
`https://developer.apple.com/design/human-interface-guidelines/<section>`, and
each row cites the section by its slug. "Flutter" means stable 3.47, which is
what this repo pins.

## What already matches the HIG (keep it)

| Area | Today | HIG |
| --- | --- | --- |
| Edge swipe back | Every pushed route uses `CupertinoPageRoute` on iOS: `SettloPageTransitionsBuilder` and `SettloPage` in `core/lib/widgets/platform_page.dart`. The swipe still works when Reduce Motion is on. | navigation-bars, motion |
| Bounce scrolling | `SettloScrollBehavior` uses `BouncingScrollPhysics` on iOS and dismisses the keyboard on drag. | scroll-views |
| Pull to refresh | `SettloScrollScaffold` uses `CupertinoSliverRefreshControl` on iOS. | refresh-content-controls |
| Scroll to top | Tapping the active tab scrolls the screen to the top (`SettloScrollRegistry`). | tab-bars |
| Collapsing header on tab roots | Spaces, Loans and Activity have a large title that collapses to an inline title (images 20, 40, 50, 51). | navigation-bars |
| Share | `share_plus` presents `UIActivityViewController` with a source rect. | activity-views |
| Reduce Motion | Sheets, pages and the tab pill all honour `MediaQuery.disableAnimations`. | motion |
| Dynamic Type | Figtree sits on the HIG size ramp from #145 (`SettloTypography.largeTitle`…), scales with the system setting, and is tested at 200%. | typography |
| Tab bar | A floating glass bar is replaced by a native `UITabBar` in **#157**. This audit makes no changes there. | tab-bars |

## Screen by screen

Effort: S is under half a day, M is one to two days, L is more than two days.
Conflict lists the in-flight work that touches the same files. **#107** is the
reminders work in `loans/lib/src/loan_detail.dart` and `profile/lib/src/screens.dart`.
**#157** is the native tab bar in `app/lib/shell.dart`, `core/lib/widgets/glass_tab_bar.dart`,
`tab_icons.dart` and the bottom inset.

### A. Auth and invite

| # | Screen | Current behaviour | HIG pattern | Gap and fix | Effort | Conflict |
| --- | --- | --- | --- | --- | --- | --- |
| A1 | Welcome (`01`) | A full-bleed brand screen with one gold call to action. Tapping it gives a light haptic. | onboarding, branding | Matches the HIG. A launch screen with a single action is the pattern Apple uses. No change. | – | – |
| A2 | Phone (`02`) | A custom circular back button, a "1 of 2" step label, and a title inside the content. | navigation-bars, text-fields | The back control is a custom circle glyph with no label. Use `CupertinoNavigationBar` (transparent, no title, the standard `CupertinoNavigationBarBackButton` chevron) on iOS. Keep "1 of 2" as the bar's trailing text. Autofill (`telephoneNumberNational`) is already set. | S | – |
| A3 | Country picker sheet (`03`) | A bottom sheet with a grabber, about 50 rows, no search, and "Selected" shown as text. | sheets, search-fields, lists-and-tables | Apple's region pickers are a pushed list with a search field and a checkmark. Use a page sheet (see X1) with a `CupertinoSearchTextField` pinned at the top. Show the selection as a trailing checkmark glyph and put the rows in `CupertinoListSection`. | M | – |
| A4 | OTP (`04`, `auth/lib/src/otp_screen.dart`) | Six boxes. The focused box is gold. | text-fields | `AutofillHints.oneTimeCode` is already set, so the "From Messages" code is offered. The only gap is the back control, as in A2. | S | – |
| A5 | Join invite (`05`) | Wordmark, two buttons, and no navigation bar. | modality | Acceptable. "This isn't me" is destructive, so confirm it with an action sheet (X3). | S | – |

### B. Home

| # | Screen | Current behaviour | HIG pattern | Gap and fix | Effort | Conflict |
| --- | --- | --- | --- | --- | --- | --- |
| B1 | Home (`10`, `11`) | The `SETTLO` lockup, the bell and an avatar in a custom header. When scrolled, the lockup centres and the header goes translucent. Content sits in cards. | navigation-bars (large title), lists-and-tables | Home is the brand surface, so keep the lockup: Apple's own apps such as Wallet and Fitness brand their root tab. Make the bell and avatar 44-pt bar buttons that can show a badge. Rows inside the cards should use `CupertinoListTile` with the system disclosure chevron. | S | #157 (bottom inset only) |
| B2 | Rows in Spaces, Loans and Recent activity | Tapping a row opens it. A long press does nothing. | context-menus | Add a long-press context menu on the space, loan and activity rows: Open, Add expense, Settle up, Share invite. Use `CupertinoContextMenu`, which gives the system lift preview and a blurred backdrop. | M | – |
| B3 | Add expense and Settle up buttons | The full screen pushes in from the right (see X1). | sheets | See X1. | – | – |

### C. Spaces and space detail

| # | Screen | Current behaviour | HIG pattern | Gap and fix | Effort | Conflict |
| --- | --- | --- | --- | --- | --- | --- |
| C1 | Spaces list (`20`) | A large title, a circular "+" button, and filter chips (All, Home, Trips). | navigation-bars, search-fields, segmented-controls | There is no search. Add a `CupertinoSearchTextField` under the large title that hides on scroll, as in Mail and Notes. Keep the chips: they are filters, not views. Make "+" a plain bar button with no circle. | M | – |
| C2 | Space rows | Tap to open. No swipe and no long press. | lists-and-tables (swipe actions), context-menus | Add a swipe action on the trailing edge: Leave, destructive and confirmed through X3. Add the same context menu as B2. Flutter has no swipe-action widget and `Dismissible` cannot show buttons, so build a small `SSwipeActions` in core. The alternative is `flutter_slidable`, which is a new dependency and needs an ADR. | M | – |
| C3 | Create space sheet (`21`) | A sheet with a grabber and an "X" on the left. A custom segmented control (Flat, Trip, Friend, Other). The primary action is a full-width button at the bottom. | sheets, segmented-controls, toolbars | Apple's create sheets put Cancel on the leading side and the confirming action (Create) on the trailing side of the navigation bar. Use a page sheet (X1) with `CupertinoNavigationBar` set to leading Cancel and trailing **Create** in gold. Replace `SSegmentedControl` with `CupertinoSlidingSegmentedControl` and give the thumb the surface token. Pick contacts from the system contact picker (`CNContactPickerViewController`); this needs a native view or `flutter_contacts`' picker, which is already planned in the context pack. | M | – |
| C4 | Space expenses (`22`, `23`) | A centred inline title, a circular back button, an avatar stack, and an Expenses/Balances/Activity switcher. Each tab is a separate **route** (`context.go`). Rows are grouped by day. | navigation-bars, segmented-controls, lists-and-tables | (1) Use the standard back chevron with the previous screen's title ("Spaces") through `CupertinoNavigationBar` or `CupertinoSliverNavigationBar`, and let the title start large and collapse. (2) Use `CupertinoSlidingSegmentedControl` for the switcher and swap content in place. A segment change is not navigation, so back should not walk through tabs. (3) Make the day headers sticky, as in Wallet and Mail (`SliverMainAxisGroup` with a pinned header). | M | – |
| C5 | Expense row | A tap opens Edit expense. Nothing else. | context-menus, lists-and-tables | Add a long-press menu (Edit, Question this, Delete; Delete is destructive) and a trailing swipe action (Delete), using the C2 widget. | M | – |
| C6 | Balances (`24`) | Fair-share bars, a card with the simplest way to settle, and "Remind" pills. | buttons | The "Remind" pills look like gold primary actions. Under the brand rule (gold is only for the primary action), they should be bordered or plain secondary buttons. Reminders are #107's scope, so change the style only after #107 lands. | S | **#107** |
| C7 | Edit expense sheet (`26`) | The same layout as the amount sheet. "Delete expense" is plain text. Deleting needs a second tap ("Tap again to delete"). | alerts, action-sheets | Replace the tap-again pattern with an action sheet (X3) that has a destructive "Delete Expense" button. | S | – |
| C8 | Confirm settlement (`spaces/lib/src/space_detail.dart` `ConfirmSettlementSheet`) | An amount sheet pushed as a page. | sheets | X1. | – | – |

### D. Expenses and Settle up

| # | Screen | Current behaviour | HIG pattern | Gap and fix | Effort | Conflict |
| --- | --- | --- | --- | --- | --- | --- |
| D1 | Add expense (`30`) | **Pushed as a full page that slides in from the right**, but drawn like a sheet: a grabber and an "X". Its drag-to-dismiss is a hand-rolled `GestureDetector` that only works on the title row (`SAmountSheet._endDrag`). | sheets, modality | This is the most visible gap. A self-contained task should be a modal page sheet that slides up, can be dragged down from anywhere, and shows the parent card behind it. On iOS, present it with `CupertinoSheetRoute` / `showCupertinoSheet`, which gives the stacked-card look and drag to dismiss. To stop a swipe from discarding a half-filled form, hook up `PopScope` and show a "Discard expense?" action sheet. See X1. | M | – |
| D2 | Date chip "Today" | Opens Material `showDatePicker`, a calendar dialog. | pickers (date pickers) | Use `CupertinoDatePicker(mode: date)` inline in the sheet, in the compact style that expands as in Reminders. Or show it in a `showCupertinoModalPopup` with Done. Shared helper: `showSettloDatePicker`. | S | – |
| D3 | Split participants | Material `Checkbox`. | toggles | iOS lists use a trailing checkmark, not checkboxes. Use `CupertinoListTile` with a trailing check glyph, or `Checkbox.adaptive`, which gives `CupertinoCheckbox`. | S | – |
| D4 | Split mode (Equally, Exact, %, Shares) | `SSegmentedControl`. | segmented-controls | `CupertinoSlidingSegmentedControl`. | S | – |
| D5 | Amount field | A large Figtree number with a decimal keypad. | text-fields | The keypad has no Done or Next. Add a keyboard toolbar (`CupertinoTextField`'s input accessory, or a `KeyboardListener` bar) with a Done button. | S | – |
| D6 | Save expense | A full-width bottom button, disabled until the split is valid. | sheets, toolbars | Keep the bottom button: it is the brand's amount-first composition. Also mirror the action as the trailing "Add" bar button, as in Reminders. Fire success haptics on save (X5). | S | – |
| D7 | Settle up (request `31`, pay `32`) | A pushed page that looks like a sheet. Method choice is a custom radio card. Record payment is at the bottom. | sheets, lists-and-tables | Present it as a sheet (X1). Make the method choice an inset-grouped list with checkmarks (`CupertinoListSection.insetGrouped`) instead of radio circles. The UPI hand-off already uses the system app chooser. Fire a success haptic when a payment is settled or recorded (X5). | M | – |

### E. Loans and loan detail

| # | Screen | Current behaviour | HIG pattern | Gap and fix | Effort | Conflict |
| --- | --- | --- | --- | --- | --- | --- |
| E1 | Loans list (`40`) | A large title, "+", and loan cards with progress. | lists-and-tables, context-menus | Add a long-press menu on each loan (Record repayment, Statement, Share). Make "+" a plain bar button (C1). | S | – |
| E2 | Loan detail (`41`) | An inline "Loan" title, a circular back button and a circular download button. A hero ring, the instalment grid, Record repayment, and a repayment list. "Confirm received" is a gold pill inside the row. | navigation-bars, activity-views, lists-and-tables | (1) Use the standard back chevron, and make the title the counterparty ("Arjun"). (2) Download should be the system **share** glyph opening the share sheet, which already exists. A bare download icon reads as Android. (3) Repayment rows: long-press menu (Confirm, Didn't get it). | M | **#107** (same file, `loan_detail.dart`): do this after #107 merges |
| E3 | Record repayment sheet (`42`) | An amount sheet presented through `showSettloSheet`. Paid by is shown as chips. Paid on uses Material `showDatePicker`. | sheets, pickers | Present it as a page sheet (X1). Use the Cupertino date picker (D2). | S | #107 (opens from `loan_detail.dart`) |
| E4 | "Didn't get it" dispute (`43`), confirmation dispute (`46`) | A small bottom sheet with a grabber, a text field, a destructive button (shown grey until text is entered) and Cancel. | sheets (detents), alerts | This sheet is the right size for a **medium/fit-content detent**. Flutter's `CupertinoSheetRoute` has no detents, so either size the sheet to its content through `showSettloSheet` (what it does today; add a background dim and keep the grabber), or use a native `UISheetPresentationController` (**native view needed** for true detents). Recommendation: keep the Flutter sheet; the visual gap is small. Make the destructive button coral and fire an error/warning haptic on submit (X5). | S | #107 for 43 |
| E5 | New loan (`44`) | A pushed page that looks like a sheet. "I lent / I borrowed" uses a custom segmented control. A Material `DropdownButtonFormField` for the due day. Material `showDatePicker` for the start date. A **disabled Material `Switch`** for interest. | sheets, segmented-controls, pickers, toggles | X1 sheet. `CupertinoSlidingSegmentedControl`. Due day becomes a `CupertinoPicker` wheel (1 to 28) in a popup, or a pull-down menu. Use the Cupertino date picker (D2). Use `Switch.adaptive`, which gives `CupertinoSwitch`; tint it to the Settlo surface or ink, never system green. See Conflicts. | M | – |
| E6 | Confirm repayment (`45`) | A pushed page. Confirm is the gold primary and "Didn't receive this" is secondary. | alerts | Matches the HIG. Fire a success haptic on Confirm (X5). | S | – |

### F. Activity

| # | Screen | Current behaviour | HIG pattern | Gap and fix | Effort | Conflict |
| --- | --- | --- | --- | --- | --- | --- |
| F1 | Activity (`50`) | A large title, a bell, and filter chips (All, Needs you, Flat 402…) that scroll sideways. Grouped by day. | navigation-bars, search-fields | Add search (C1). Make the day headers sticky (C4). The filters are fine as chips. | S | – |
| F2 | Activity row | Tapping a row with a question opens a sheet. | context-menus, lists-and-tables | Add a long-press menu (Open, Question this edit). Add a leading swipe action "Mark read" if read state lands. | S | – |
| F3 | Question edit sheet (`51`) | A small sheet with a text field and Send. | sheets | The same pattern as E4: keep it. | – | – |

### G. Profile and settings

| # | Screen | Current behaviour | HIG pattern | Gap and fix | Effort | Conflict |
| --- | --- | --- | --- | --- | --- | --- |
| G1 | Profile (`12`, `13`) | "You" as an inline title. A circular back button. Custom cards (`_SettingsCard`, `_SettingRow`) with icon tiles, two-line rows and chevrons. Section labels in uppercase. | lists-and-tables (inset grouped), settings | This is the screen furthest from Settings. Rebuild it as `CupertinoListSection.insetGrouped` and `CupertinoListTile`: a leading icon tile, a title, a trailing value (Appearance → "Dark"), and the system chevron. Drop the subtitles that only repeat the title. Use a large title "You" that collapses. | M | **#107** (Reminders row and settings in `profile/lib/src/screens.dart`): do this after #107 |
| G2 | Reminders, Contacts matching and App lock rows | **Rows with no control and no chevron.** They look tappable but do nothing. | toggles | Use a trailing `CupertinoSwitch` (via `Switch.adaptive`) for the on/off preferences. If a feature is not built yet, hide the row instead of showing a dead one. | S | **#107** owns Reminders |
| G3 | UPI card | A card with a gold "Change" button. | lists-and-tables | Make it a row in the first section ("UPI ID · satheesh@okaxis ›") so it matches Settings, which shows the value in the row. | S | #107 |
| G4 | Name and UPI ID sheet (`14`) | A bottom sheet with Material outlined fields (floating labels) and a full-width Save. | sheets, text-fields | Use a page sheet with Cancel on the left and **Done** on the right (X1). Use `CupertinoTextField`-styled grouped fields with the label in the row, as in Contacts. | M | #107 |
| G5 | Appearance sheet (`15`) | A sheet listing System, Light and Dark, with a checkmark. | lists-and-tables | Apple pushes a list here, as in Settings › Display. A pushed `CupertinoListSection` with a checkmark is closer to the HIG than a sheet. Low priority. | S | #107 |
| G6 | Export sheet (`16`) | A sheet listing each space and loan as "CSV and PDF". | action-sheets, activity-views | Fine as a sheet. Make each row open the share sheet directly, and show a trailing `CupertinoActivityIndicator` while it builds (replace `CircularProgressIndicator` with `.adaptive`). | S | – |
| G7 | Sign out with unsent changes (`17`), delete account (`18`) | A bottom sheet with Keep in **gold** and the destructive action as a secondary bordered button. | alerts, action-sheets | Apple uses an **action sheet** for a destructive choice the user started from a button (Sign Out in Settings), and an **alert** for an irreversible one (Delete Account). Use `showCupertinoModalPopup` + `CupertinoActionSheet` for sign out ("Sign Out Anyway" in red, Cancel), and `showCupertinoDialog` + `CupertinoAlertDialog` for delete (destructive "Delete Account", Cancel in bold). Keep the body copy. | S | #107 (same file) |
| G8 | Loading | Material `CircularProgressIndicator` on Profile, Export and auth. | progress-indicators | Use `CircularProgressIndicator.adaptive()`, which gives `CupertinoActivityIndicator`. | S | – |

### X. App-wide patterns

| # | Pattern | Current behaviour | HIG | Fix | Effort | Conflict |
| --- | --- | --- | --- | --- | --- | --- |
| X1 | **Modal sheets** | Two systems are in use. (a) `showSettloSheet` is a Material bottom sheet: grabber drawn by hand, no stacked-card effect, fits its content. (b) `SAmountSheet` screens (Add expense, Settle, New loan, Confirm settlement) are **pushed pages** that slide in from the right and imitate a sheet. | sheets, modality | On iOS, show every full task (X1b, and the Create space and Edit profile sheets) with **`CupertinoSheetRoute`** (go_router `pageBuilder` → `CupertinoSheetPage` wrapper in `SettloPage`). It gives the system stacked card, drag down anywhere, and the parent scaled behind it. Keep small confirmations (dispute, question) on `showSettloSheet`. Detents (medium/large) are **native view needed**. Recommendation: do not build them now. | L | – |
| X2 | **Navigation bar** | `SettloScrollScaffold` draws its own pinned header. Pushed screens have a circular back button and an inline title, but **no back title and no large title** on detail screens. | navigation-bars | Keep `SettloScrollScaffold` as the single owner. On iOS, render the bar through `CupertinoSliverNavigationBar` (large title that collapses, `previousPageTitle`, the standard chevron), themed with Figtree and the surface tokens. Its translucent bar suits the glass rule (glass for chrome only). This change touches every screen through one widget. | L | #157 only shares the status inset; otherwise none |
| X3 | **Alerts and action sheets** | None. Every confirmation is a bottom sheet. | alerts, action-sheets | Add the helpers `showSettloConfirm` (alert) and `showSettloActions` (action sheet) in core. On iOS they use `CupertinoAlertDialog` and `CupertinoActionSheet`; on Android they use Material. | S | – |
| X4 | **Context menus and swipe actions** | None anywhere. | context-menus, lists-and-tables | Add a core `SContextMenu` (a `CupertinoContextMenu` wrapper on iOS, long press opens a Material menu on Android) and `SSwipeActions` (custom; no new dependency). | M | – |
| X5 | **Haptics** | Only `lightImpact` on a tab change, pull to refresh, and Welcome. | playing-haptics | Add success when a payment is settled, recorded, confirmed or an expense is saved. Add warning or error for a dispute or a failed save. Add `selectionClick` for segment and picker changes. Flutter's `HapticFeedback` has no `UINotificationFeedbackGenerator` success, warning or error, so add `SettloHaptics.success/warning/error` through a small method channel in `packages/platform` (native, S), with impact fallbacks on Android. | S | – |
| X6 | **Icons** | Custom-painted line glyphs per feature (`*Glyph`), the same on both platforms. A few Material `Icons.*` (Activity arrow). No SF Symbols. `cupertino_icons` is not a dependency. | sf-symbols | For **system actions** (back chevron, close, share, plus, ellipsis, checkmark, trash, search), use SF Symbols. Option A: add `cupertino_icons`, which needs an ADR under the dependency policy; its glyphs are SF-like but not real SF Symbols. Option B: render real SF Symbols through a native view or image channel (**native view needed**). Recommendation: **A** for in-content glyphs, and keep the custom brand glyphs for Settlo concepts (space kinds, loan ring). #157 already uses real SF Symbols for tabs. | M | **#157** (tab icons, `tab_icons.dart`) |
| X7 | **Controls** | Material `Switch`, `Checkbox`, `DropdownButtonFormField`, `showDatePicker` and outlined `TextField`s on iOS. | toggles, pickers, text-fields | Use the `.adaptive` constructors where they exist. Elsewhere use explicit Cupertino controls behind small core wrappers: `SSwitch`, `SDatePicker`, `SPicker`, `STextField`. | M | – |
| X8 | **Snackbars** | `ScaffoldMessenger` snackbars for sync refusals, invite notices and export errors. | alerts, notifications | iOS has no snackbars. Use an alert for an error that needs a decision. Use a small top banner (a toast like Mail's "Undo send") for information. Recommendation: a core `showSettloNotice` that shows a top banner on iOS. | S | – |
| X9 | **Motion** | Pages use Cupertino routes. Sheets use a 200 ms panel curve. Presses scale. | motion | `CupertinoSheetRoute` brings the system spring (X1). Keep Reduce Motion as it is. | – | – |

## Where keeping Figtree or the Settlo colours conflicts with the HIG

1. **Figtree compared with SF Pro.** The HIG recommends the system font, but it
   allows a custom font for brand when the custom font supports Dynamic Type and
   keeps legibility (typography). The ramp in #145 already follows the HIG sizes.
   *Recommendation: keep Figtree everywhere.* The one exception is that system
   chrome renders in SF automatically: the native tab bar (#157), alerts and
   action sheets if X3 goes native, and the share sheet. Accept that mix. Apple's
   own apps that use custom fonts, such as News and Fitness, do the same. Do not
   force Figtree into `CupertinoAlertDialog`.
2. **Tint colour.** iOS controls default to system blue. The issue forbids system
   blue as the brand colour. Gold is reserved for the primary action.
   *Recommendation:* set `CupertinoThemeData.primaryColor` to **gold in dark and
   ink in light**, but only for the primary action: the trailing bar button and
   the default alert button. Neutral controls (back chevron, Cancel, segment
   thumb) use `textPrimary`. This is how Apple's branded apps work: Wallet,
   Fitness and Notes all tint with their own colour.
3. **The `CupertinoSwitch` on colour is system green**, and green means "owed to
   you" in Settlo. *Recommendation:* set `activeTrackColor` to the light ink /
   dark `textPrimary` token, not mint and not gold. The HIG allows a custom tint
   (toggles).
4. **Destructive red compared with Settlo coral.** The HIG uses system red for
   destructive actions; Settlo saves coral for "you owe". *Recommendation:* use
   coral for destructive actions. It reads as red, so the HIG intent holds, and
   the brand rule bends slightly. **The owner needs to approve this.** The other
   option is system red only inside native alerts and action sheets.
5. **Dark-first background #0A0B0D compared with iOS grouped backgrounds.**
   Inset-grouped lists expect `systemGroupedBackground`. *Recommendation:* map the
   grouped background to `background` and the cells to `surface` (#15171A). That
   is the same contrast step as iOS dark mode. Keep it; it does not conflict.

## Implementation PRs (in order of user impact)

**PR 1: Sheets, navigation bar and confirmations** (L).
X1, X2, X3, plus D1, D7, E5 (sheet only), C3, C4 (back title and large title),
C7, G7, A2, A4, and the haptics in X5.
This is what makes Settlo feel like Apple's own apps: tasks slide up and drag
away, back shows where you came from, and destructive choices use alerts and
action sheets.
Files: `core/lib/widgets/{platform_page,sheet,amount_sheet,scroll_scaffold}.dart`,
feature routes, and a new `platform` haptics channel.
*Conflicts:* none with #107 if it avoids `loan_detail.dart` and Profile. It
touches the inset handling that #157 also changes, so rebase onto #157 first.

**PR 2: Controls and lists** (M).
X7, D2, D3, D4, D5, E5 (controls), C1 (search), A3, F1, G6, G8, X8, and X6
option A (cupertino_icons ADR).
These are the touches that make Settlo look native: Apple switches, pickers,
segmented controls, search and checkmarks.
*Conflicts:* none.

**PR 3: Context menus, swipe actions, and the settings-style Profile** (M).
X4, B2, C2, C5, E1, E2, F2, G1 to G5, and C6 (style).
*Conflicts:* **#107**: start only after #107 merges (Profile, `loan_detail.dart`,
Remind buttons).

The tab bar is #157's scope: it is native, uses SF Symbols, and minimises on
scroll. It is not repeated here.

## Tests each implementation PR must add (from the issue)

- Widget tests under `TargetPlatform.iOS`: edge swipe back pops, sheets dismiss
  on drag (`CupertinoSheetRoute`), context menus open on long press, and swipe
  actions show their buttons.
- Haptics: a fake `SystemChannels.platform` / the haptics channel records the
  expected success, warning, error and selection calls.
- Goldens are regenerated deliberately per PR, in both 390×844 and 360×800,
  light and dark.
- Evidence: before and after from the iOS simulator for every main screen, and
  short recordings of navigation, sheets and swipes.

## Open questions for the manager

1. Destructive colour: coral, or system red inside native alerts only (item 4 in
   the conflicts section)?
2. X6: is a `cupertino_icons` ADR acceptable, or should we wait for real SF Symbols
   through a native view?
3. X1: do we accept no detents (full-height sheets plus content-sized small
   sheets), or should true detents get a native view in a later PR?

## Manager decisions (11 Nov 2026)

1. Destructive colour: system red only inside native Cupertino alerts and
   action sheets. Coral everywhere else.
2. `cupertino_icons` is approved for system actions only (back, share, more,
   add, delete, checkmark), with an ADR in `docs/decisions/`. Custom glyphs
   stay for brand and tab icons. No native SF Symbols view.
3. No true detents this round: full-height `CupertinoSheetRoute` and
   content-sized small sheets. Native detents are a follow-up issue.
4. Settlo tokens for every tint, switch-on colour and selection colour; never
   system blue. Figtree stays on the #145 ramp.

## PR 1 as built

- **X1 (D1, D7, E5 sheet, C8).** `SettloSheetPage` in
  `core/lib/widgets/platform_page.dart` presents Add expense, Settle up (and
  its pay step), New loan and Confirm settlement as a `CupertinoSheetRoute`
  on iOS: it slides up, scales the screen behind into a stacked card, and
  drags down to dismiss from the title or from the top of the content. The
  scroll scaffold inside takes the sheet's scroll controller, and
  `SAmountSheet`'s hand-rolled drag is off inside the native sheet. Android
  keeps the existing page route. Create space and Edit profile stay on
  `showSettloSheet` for now (Profile is #159's file).
- **X2 (C4 back and large title).** `SettloScrollScaffold` takes `largeTitle`,
  `previousPageTitle` and `trailing`. On iOS it renders a
  `CupertinoSliverNavigationBar` themed with Figtree and Settlo tokens, and
  leaves out the custom header. Space detail (expenses, balances, empty) uses
  it: the space's name collapses, and back reads "Spaces". Loan detail and
  Profile wait for #159.
- **X3 (C7, G7).** `showSettloActionSheet` and `showSettloAlert` in
  `core/lib/widgets/confirm.dart`. On iOS, sign out with unsent changes and
  delete expense use the action sheet; delete account uses the alert. They
  answer once on a double tap and tint non-destructive buttons with primary
  text. Android keeps the Settlo sheets and the tap-again delete.
- **Not in PR 1.** Haptics (X5) need a channel registered in `AppDelegate`,
  which #160 is changing, so they move to PR 3. A2 and A4 (auth back
  controls), C3 (Create space as a page sheet) and the "Discard expense?"
  guard on swipe are left for PR 2.
