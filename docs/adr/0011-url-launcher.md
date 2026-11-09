# 0011 Opening UPI apps and WhatsApp: url_launcher, and the Android chooser

## Status
Proposed (9 Nov 2026), with Settle up (#63). Revised after review of PR #75.

## Context
Settle up never moves money (context pack). The pay side hands the payment to the payer's own UPI app through a `upi://pay` intent with the payee's VPA, name, amount and a note prefilled, through the OS **app chooser** (context pack; canvas note n44). The request side opens WhatsApp (`https://wa.me/<number>?text=…`) with the amount and the payee's UPI id. Flutter's SDK cannot open a URL in another app. [0005](0005-dependency-policy.md) asks for an ADR for every new direct dependency.

`url_launcher` alone does not meet the chooser requirement: on Android it calls `startActivity(ACTION_VIEW)`, which goes straight to a default UPI app if one is set, and on iOS it calls `UIApplication.open`.

## Decision
- **Android `upi://`**: a plugin-less `MethodChannel` (`app.settlo/upi`, method `openWithChooser`), with its Dart side in `packages/platform` (`openUpiChooser`) and its Kotlin in `MainActivity`. It wraps the `ACTION_VIEW` intent in `Intent.createChooser`, so the payer picks the app every time. If `resolveActivity` finds no UPI app it returns `false`, and the sheet shows a plain message and offers to record a cash payment. No new dependency.
- **iOS `upi://`**: iOS has no app-chooser API. The app opens `upi://` directly and **the system picks the app registered for the scheme**, which is usually the last UPI app installed. This is a platform limit, not a choice.
- **Other links (iOS `upi://`, WhatsApp)**: **`url_launcher`** (`^6.3.3`) in `packages/features/settle`, with `LaunchMode.externalApplication`. It is already in the lockfile at that version as a transitive dependency of `supabase_flutter` ([0007](0007-supabase-flutter.md)), so the lockfile and the app binary do not change. A `false` result shows a plain message.
- **Package visibility, minimal**: Android `<queries>` has one `VIEW` intent for the `upi` scheme, which `resolveActivity` needs on Android 11+ to see UPI apps. iOS `LSApplicationQueriesSchemes` has only `upi`. Nothing is declared for `https`.
- Both openers sit behind providers (`openUpiProvider`, `openUrlProvider`) that tests override. The channel is tested against a mock handler.
- A settle-up is recorded (`add_expense` with `is_settlement`) only after the user comes back and confirms the payment. Opening the app records nothing.

## Alternatives considered
- **`url_launcher` only.** No chooser on Android when a default UPI app is set (review of #75).
- **App-specific schemes (`tez://`, `phonepe://`, `paytmmp://`) per tile, as the canvas draws.** These are undocumented, change without notice and need one query entry per app. The chooser covers every UPI app.
- **A published plugin for intents (e.g. `android_intent_plus`).** A new dependency for about 20 lines of Kotlin.
- **`share_plus` for the WhatsApp request.** It cannot prefill a WhatsApp recipient; `wa.me` with `url_launcher` can.

## Consequences
- One direct dependency on `url_launcher`, now in `settlo_platform` (see the amendment), and `settlo_settle` depends on `settlo_platform`. No new package in the lockfile.
- The SettlePay artboard's per-app tiles are replaced by one button that opens the chooser on Android and the registered app on iOS.
- Whether the payment happened is the user's word. By design, Settlo cannot see the UPI result.

## Amendment (10 Nov 2026, #88)
New loan also opens WhatsApp, to tell the other person a loan was recorded with them. `openUrlProvider` and the `url_launcher` dependency move from `settlo_settle` to `packages/platform` (with `flutter_riverpod`), which both features use; ADR 0002 sends shared code down, not sideways. `settlo_settle` re-exports the provider, so its tests are unchanged. The loan message carries no amount, terms or link: nothing about a loan is shown before the number verifies (n43), and a store link waits for M6. Still no new package in the lockfile.
