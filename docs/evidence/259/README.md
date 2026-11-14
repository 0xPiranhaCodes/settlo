# Feedback after actions (#259)

Before is `origin/main` at `ff083d3`; after is this branch. Both builds use the
same scratch entry, `feedback_259_app.dart.txt` (copy it to
`app/integration_test/` and build with `flutter build ios --simulator --debug
-t integration_test/feedback_259_app.dart`). It is the offline demo app in
light mode with fixture data, a synthetic profile number (+91 90000 00001),
and a Help and support link that always fails to open, so Profile's error
notice can be shown.

Recorded on a task-owned iPhone 14 simulator (390×844, iOS 26.1), created by
UDID and deleted afterwards. `t.sh` drives it with real HID taps through
`docs/evidence/188/simtouch.m`; each install starts fresh, so notification
permission is undetermined.

- `status-bar.png` (W1): Home → **Add expense** → ✕ → Loans. Before, the time
  and battery stay white on cream across tabs. After, they are dark in light
  mode and light in dark mode (set in Profile → Appearance).
- `confirm-repayment.png` (W2): Loan → "awaiting you" → **Confirm ₹25,000
  received**. Before, the page stays and turns read-only. After, a notice says
  "Confirmed. ₹6,50,000 left" over the loan it returned to.
- `remind.png` (W3): Loan → **Remind**. Before, the permission explanation
  interrupts the nudge. After, the reminder is sent with no prompt.
- `profile.png` (W3, W18): Before, opening Profile shows the Material
  explanation, and a failed Help and support shows a Material snackbar. After,
  opening Profile asks nothing, turning Reminders off and on shows the native
  alert, and the error is the iOS banner.
