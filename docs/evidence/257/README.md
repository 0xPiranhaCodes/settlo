# New loan keeps the typed name (#257)

Before is `origin/main` at `cecd375`; after is this branch. Both builds use the
same scratch entry, `loan_name_257_app.dart.txt` (copy it to
`app/integration_test/` and build with `flutter build ios --simulator --debug
-t integration_test/loan_name_257_app.dart`). It is the offline demo app, but a
new loan is read back through the real shared code: `createLoanParams` → the
row `create_loan` stores → `loansFromRows`. So the recordings show the
payload and display code, not a fake's behaviour.

Recorded on a task-owned iPhone 14 simulator (390×844, iOS 26.1), created by
UDID and deleted afterwards. `flow.sh` drives it with real HID taps through
`docs/evidence/188/simtouch.m`, including on-screen keyboard taps: Loans → **+**
→ 5000 → 98765 00011 → "Ravi" → **Add person** → **Create loan and share** →
back from WhatsApp → Loans.

- `before.mp4`: the row reads "+919876500011 · int…" with a "+" avatar and
  the detail header reads "+9198…".
- `after.mp4`: the row and the detail header read "Ravi", with an "R" avatar.
- `before-after.png`: detail and list, before (top) and after (bottom).
