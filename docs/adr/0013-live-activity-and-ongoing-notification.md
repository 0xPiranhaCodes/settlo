# 0013 Live Activity and the Android ongoing notification: plugin-less, driven by app state

## Status
Proposed (10 Nov 2026), with #105.

## Context
The LiveActivity artboard (note n32) puts two states on the lock screen and in the Dynamic Island: a settle-up waiting for you, and a trip in progress. Confirm sits in the expanded island. Android shows the same state as an ongoing notification. Issue #105 adds: started, updated and ended from app state, no push in v1, and the notification permission asked in context rather than at launch. n32's review note also asks the glass tab bar to fall back to a flat 92% surface on mid-range Android.

The context pack names the `live_activities` package and an Edge Function sending through APNs. Push is out of scope for v1, and the app already talks to native code over a plugin-less `MethodChannel` (`app.settlo/upi`, [0011](0011-url-launcher.md)).

A trip has no data model beyond `space_kind = 'trip'`: no start or end date, so "day 3 of 4" and "in progress" cannot be computed. This ADR covers the settle-up state only. The trip state moves to #117, which needs trip dates first; this work is part of #105, not all of it.

## Decision
- **One channel, `app.settlo/live_activity`**, with methods `show(state)`, `end()` and `requestPermission()`. The Dart side is `LiveActivities` in `packages/platform`. `show` gets fields ready to draw: the payer, the amount already formatted by `formatInr`, the space name, when it was recorded, and the confirm route. Native code does no money formatting. `needs_you.counterparty` falls back to the payer's phone number; a number is never sent, and the payer reads "A flatmate" instead, because these surfaces are readable on a locked phone.
- **Which settle-up**: `settleUpActivityFor` picks the newest settle-up in `needs_you` (docs/api.md). Repayments are not a Live Activity state (n32). `liveActivitySyncProvider` in `settlo_activity` follows `needsYouProvider`. The provider reloads after your own answers (`ledgerRevisionProvider`) and whenever the app resumes. It ends the activity when nothing is left, when you sign out, and whenever the signed-in user id changes. `needsYouProvider` is keyed by that id too, so one user's settle-up is never shown to the next. The app keeps the provider alive.
- **iOS**: a WidgetKit extension, `SettloWidgets` (`app.settlo.SettloWidgets`, iOS 16.1), draws the Dynamic Island (compact, minimal, expanded) and the lock screen from `SettleUpAttributes`. Both targets compile that file. The Runner starts, updates and ends the activity with ActivityKit. Live Activities are gated at iOS 16.2, the first release with `ActivityContent`. There is no fallback on 16.1: the app runs there without a Live Activity. The deployment target stays 16.1. Activities outlive the process, so one left from an earlier launch is updated, not duplicated. iOS asks for no permission. People turn Live Activities off in Settings.
- **Confirm deep link**: `settlo://app/<route>`, handled by Flutter's built-in deep linking and go_router. iOS registers the `settlo` URL scheme, because the island's `Link`/`widgetURL` needs one. Android uses an explicit `PendingIntent` to `MainActivity` and declares no intent filter for the link. `MainActivity` is the exported launcher, so another app can still target it with a link, and on iOS any app can open a `settlo://` URL. A link only navigates: the confirm sheet reloads the settle-up, checks that it is pending and that you are the payee, and confirming still takes your tap.
- **Android**: `SettleUpNotification` (Kotlin, framework APIs only) posts one ongoing notification on channel `settle_ups` (low importance, silent). It has the canvas text and a Confirm action. `POST_NOTIFICATIONS` (Android 13+) is requested once, from the Activity tab when a settle-up is waiting, never at launch. A state that arrives before the user answers is posted once permission is granted.
- **Flat tab bar**: `app.settlo/device` → `prefersFlatChrome` returns true on Android when `isLowRamDevice` or total RAM is under 5 GiB, which is a phone sold as under 6 GB. `main` reads it once and passes it to `SGlassTabBar.lowEndBlur`. iOS always uses glass.
- **No new dependency.** `settlo_platform` now depends on `settlo_core` and `settlo_activity` on `settlo_platform`, both allowed by [0002](0002-package-boundaries.md).

## Alternatives considered
- **`live_activities` package.** It wraps the same ActivityKit calls and requires an App Group plus UserDefaults plumbing for images. That is a dependency for about 60 lines of Swift, and its Android side does not cover the ongoing notification.
- **`flutter_local_notifications` for Android.** A large plugin for one notification with one action.
- **Push (APNs / FCM) to start and update.** This is the only way to show a settle-up recorded while the app is closed. It is deferred: v1 has no push. The channel's `show`/`end` do not change when push arrives later.
- **Inventing trip dates.** No schema backs them. This needs a Backend issue first.

## Consequences
- A settle-up recorded while Settlo is closed shows up only after the app is next opened or resumed. Push lifts this limit later.
- The canvas's "Not yet" button is left out of the island and the notification. Disputing needs a reason, which the confirm sheet already collects, and an in-place dismiss would need App Intents (iOS 17). Confirm and a tap anywhere both open the confirm sheet.
- The island uses the system serif in place of IBM Plex Serif, so the extension does not bundle fonts.
- The Runner embeds an app extension. CI's `flutter build ios --no-codesign` builds it, and signing for release needs the `app.settlo.SettloWidgets` identifier in the provisioning profile.
