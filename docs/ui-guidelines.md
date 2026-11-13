# SabkiJeb app UI guidelines

The single rulebook for in-app UI. Values live in code: `packages/core/lib/theme/tokens.dart`, `colors.dart` and `typography.dart`. This page says *when* to use each value. Token values come from code; the usage rules here are the target. Code that differs is tracked as an issue in the audit. Website styling is in [brand.md](brand.md). The audit behind these rules is [audits/ux-2026-11-13.md](audits/ux-2026-11-13.md).

## Platform

**iOS** follows the manager's HIG decisions ([decisions/2026-11-11-ios-hig.md](decisions/2026-11-11-ios-hig.md)):

- **Destructive actions:** system red appears only inside native Cupertino alerts and action sheets. The theme error colour (`error`) is the destructive colour everywhere else. Irreversible choices ask with `showSettloAlert`. A two-tap "tap again" confirm is not a substitute.
- **Icons:** `cupertino_icons` for system actions only: back, share, more, add, delete and checkmark. Settlo glyphs are for brand concepts and tab icons ([cupertino-icons ADR](decisions/2026-11-11-cupertino-icons.md)).
- **Sheets:**
  - A full task (Add expense, Settle up, New loan, Create space) is a full-height `SettloSheetPage` / `showSettloPageSheet`. It has a grabber, ✕ at the top left, a centred title and one primary button at the bottom.
  - A small confirmation is a content-sized `showSettloSheet`.
  - A sheet with unsaved input holds a drag-down and asks before discarding.
- **Tint:** every tint, switch and selection uses a Settlo token, never system blue.
- **Type:** text uses Figtree and the #145 ramp. Native alerts and action sheets keep the system font.
- **Alerts and notices:** use `showSettloAlert` for decisions and `showSettloNotice` for information. On iOS, never use a Material `AlertDialog` or `SnackBar`.
- **Pickers:** use `showSettloDatePicker` / `showSettloPicker`. The selected row must stay visible through the highlight band.
- **Status bar:** every root screen declares its overlay style for the current brightness (`AnnotatedRegion<SystemUiOverlayStyle>`), so a closing sheet can't leave white icons on cream.
- **Back:** use one back control on pushed screens: chevron plus the previous screen's name. #252 makes it liquid glass.

**Android** keeps Material behaviour: Material sheets with a drag handle, `showDatePicker`, `SnackBar` (through `showSettloNotice`), and the system back gesture. Colours, type and spacing are shared with iOS.

## Spacing

The 8 pt grid from `SettloSpacing`. Every gap *between* siblings is a token. A literal is allowed only for an optical nudge inside one component (2 pt, or `half` 4), with a one-line comment.

| Use | Token | Value |
|---|---|---|
| Screen margin, left and right, on every screen and sheet | `screenMargin` | 20 |
| Tab-root header → first content (search, chips or first card) | `x5` | 40 |
| Between sections, and after a hero card's group | `x3` | 24 |
| Between cards in one list or section | `x2` | 16 |
| Section label (eyebrow) → its card | `x1` | 8 |
| Search field → filter chips | `x2` | 16 |
| Filter chips → first card | `x2` | 16 |
| Card padding | `x3` | 24 |
| Card padding, compact list rows | `x2` | 16 |
| Between rows inside a card | `x2` | 16 |
| Icon or avatar → its text | `x2` | 16 (12 inside 36 pt rows) |
| Between buttons in a group, side by side or stacked | `x2` | 16 |
| Hero card → its action buttons | `x2` | 16 |
| Sheet content → bottom primary button | `x3` | 24 |
| Optical nudge inside a component | `half` | 4 |

Buttons in a pair split the width equally. A single secondary under a full-width primary is also full width, not content-hugging.

## Radius, motion and elevation

- **Radius (`SettloRadius`):**
  - `cardHero` 28: the one hero card per screen, and sheet tops.
  - `card` 24: list cards.
  - `button` 16: buttons.
  - `iconTile` 14: 40 pt icon tiles.
  - `compact` 12: nested controls (segments, inputs on a card).
  - `pill`: chips, the tab bar and capsules.
- **Motion (`SettloMotion`):**
  - `press` 150 ms at scale 0.97 for press feedback.
  - `panel` 200 ms for panels and content swaps.
  - `selection` 250 ms for a sliding selection pill.
  - All use `curve` (ease-out cubic, no bounce). With Reduce Motion (`MediaQuery.disableAnimationsOf`), durations go to zero and scale stays at 1.
- **Elevation (`SettloElevation`):**
  - Cards: a `hairline` 1 pt edge plus `ambient` shadows.
  - The floating tab bar: `floatingLight` / `floatingDark`.
  - Sheets, amount sheets and notices also use `ambient`.
  - The Welcome CTA uses its own `welcomeActionShadow`, with offset and blur from `SettloWelcomeMetrics`.

## Colour

Tokens come from `SettloColors.of(context)`. The palette is the owner's Settle Check palette (#202), with the dark rules from #248 (PR #250).

**Light:** ivory background (`#FBF8EF`), cream surfaces, jade (`#01672D`) actions and owed-to-you amounts, brick (`#934636`) you-owe amounts, amber-brown (`#795309`) pending, and red (`#A42E35`) error.

**Dark (#248):**

- **Background and surfaces:** true black, with neutral grey surfaces stepping up from about `#1C1C1E`.
- **No green anywhere.** Wherever light mode uses green, dark mode uses marigold `#FEBD11`: actions, the brand accent, the nav active state and owed-to-you amounts.
- **Pending** is neutral grey text with its clock icon.
- **You-owe and error** keep their dark colours (`#F2AB98`, `#FF9CA3`).

**Exceptions:**

1. **The logo artwork** (`SettloMark` and the app icon) keeps its own colours in both themes.
2. **Labels on marigold** (`onAction`, `onNavActive`) are neutral near-black (`#111111`) on a marigold fill in dark mode, as shipped in #250.

**Rules:**

- Money direction always pairs colour with a sign or word ("+₹", "you owe"). Never colour alone.
- Pending always pairs with the clock icon.
- `surfaceHighest` carries primary text only. Don't put an opaque `surfaceHighest` band over content (see the picker bug, #255).

## Glass

Liquid glass is chrome, never content:

- **Allowed:** the floating tab bar (native `UITabBar` on iOS, `SGlassTabBar` elsewhere), header glass actions (`GlassAction`: bell, profile, add, statement) the non-interactive Home mark (`GlassAction`), and, once #252 lands, the back control.
- **Never:** behind amounts, cards, list rows or sheet content.
- **Fallbacks:** on iOS before 26 and on Android, `GlassAction` uses its supplied Flutter button/widget fallback; the glass tab bar uses `glassFallback`. Low-end Android uses the flat bar (ADR 0013).
- **Theme:** in dark mode, glass is neutral grey (#248).
- **Layout:** glass must not cover content's last row. Reserve the bar's reported height, including any floating margin on home-button iPhones (#258).

## Accessibility

- **Contrast:** WCAG AA. 4.5:1 for body text, 3:1 for large text (≥ 24 pt, or 19 pt bold) and for UI edges. Every text/background pair in `SettloColors.textPairs` is checked by `packages/core/test/theme/contrast_test.dart`. Add a pair when you add a combination.
- **Touch targets:** at least 44 × 44 pt (`minTouchTarget`). A control may *look* smaller, like the 36 pt chip or segment, but its hit area must be 44.
- **Dynamic Type at 200%:**
  - Every screen works at iOS AX2 (about 2× body) with nothing clipped.
  - Text wraps before it truncates.
  - A single-line control (segments, chips, tabs) falls back to a stacked or scrolling layout instead of clipping a label.
  - Icons next to text scale with it, up to about 1.5×.
  - Primary actions stay reachable: scroll, or pin them above the keyboard.
- **Reduced motion:** honour `MediaQuery.disableAnimationsOf`: no scale, slide or parallax, and instant transitions.
- **Semantics:**
  - Every icon-only control has a label ("Back", "Notifications", "Download statement").
  - Live results announce through a live region; `showSettloNotice` already does.
  - Verify with real HID touches, not only XCUITest (#188).
- **Keyboards:**
  - A keyboard without a return key (phone pad, number pad) gets a Done accessory, or the field auto-advances when complete.
  - The focused field and its primary action stay visible above the keyboard.

## Feedback after an action

- Every action that saves something gives feedback in the same view: a state change on screen ("awaiting Arjun"), a `showSettloNotice`, or a success line. A screen that only becomes read-only is not feedback (#259).
- Leaving a task sheet after saving returns to where the user started. Lightweight saves get a selection haptic on iOS.
- Error text clears as soon as the user changes the input or mode that caused it.

## Small screens

Test every screen at 375×667 (iPhone SE) as well as 390×844:

- The primary action of a first-run screen is visible without scrolling.
- The tab bar sits fully above the bottom edge.
