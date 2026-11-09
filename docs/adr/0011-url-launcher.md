# 0011 Opening UPI apps and WhatsApp: url_launcher

## Status
Proposed (9 Nov 2026), with Settle up (#63).

## Context
Settle up never moves money (context pack). The pay side hands the payment to the payer's own UPI app through a `upi://pay` intent with the payee's VPA, name, amount and a note prefilled, and the OS shows its app chooser when more than one UPI app is installed (canvas note n44). The request side opens WhatsApp (`https://wa.me/<number>?text=…`) with the amount and the payee's UPI id. Both need a platform call that opens a URL in another app; Flutter's SDK has none. The context pack names `url_launcher` for UPI, and [0005](0005-dependency-policy.md) asks for an ADR for every new direct dependency.

## Decision
- Use **`url_launcher`** (`^6.3.3`) in `packages/features/settle`, the first package that imports it. It is already in the lockfile at that version as a transitive dependency of `supabase_flutter` ([0007](0007-supabase-flutter.md)), so the lockfile and the app binary do not change.
- Links open with `LaunchMode.externalApplication` behind one provider (`openUrlProvider`), which tests override. A `false` result (no app can open it) shows a plain message; the user can still record a cash payment.
- We do not call `canLaunchUrl`, but declare the schemes so it works for later callers: Android 11+ `<queries>` for `VIEW` on `upi` and `https` in `AndroidManifest.xml`, and `upi` in iOS `LSApplicationQueriesSchemes`.
- A settle-up is recorded (`add_expense` with `is_settlement`) only after the user comes back and confirms the payment; opening the app records nothing.

## Alternatives considered
- **A platform channel of our own** (Android `Intent.createChooser`, iOS `UIApplication.open`). Forces a chooser on Android, but means Kotlin and Swift to maintain for what `url_launcher` already does, and the system resolver already offers a choice when no default UPI app is set.
- **App-specific schemes (`tez://`, `phonepe://`, `paytmmp://`) per tile, as the canvas draws.** Undocumented, change without notice, and need one query entry per app. The OS chooser covers every UPI app, including ones we have not heard of.
- **`share_plus` for the WhatsApp request.** It shares to any app but cannot prefill a WhatsApp recipient; `wa.me` with `url_launcher` can, with no extra dependency.

## Consequences
- No new package in the lockfile; one direct dependency in `settlo_settle`.
- The SettlePay artboard's per-app tiles (GPay, PhonePe, Paytm, Other UPI) are replaced by one button that opens the OS chooser.
- Whether the payment happened is the user's word. Settlo cannot see the UPI result, by design.
