# Navigation, labels and inviting — #260

Audit items W4, W5, W12, W13 and W14 (`docs/audits/ux-2026-11-13.md`).

## Simulator evidence

Owned iPhone 17 simulator, iOS 26.1, created by UDID for this capture and
deleted afterwards. The app is the real `SettloApp` and router over the test
fixtures (`app/test/support`), launched from `capture.dart.txt`; no real
account or data. "Before" is `7326433` (main at #273), built from a separate
checkout. Every step is a real Simulator HID tap (`docs/evidence/188/simtouch.m`).
The simulator has no WhatsApp app, so a WhatsApp link opens in Safari.

| Item | Before | After |
|---|---|---|
| W4 Balances → **Remind** (Priya) | [opens Settle up on "Record cash"](before-remind.png) | [opens WhatsApp with the reminder text](after-remind.png) |
| W5 Expenses → Balances, same tap point | [expenses](before-segment-expenses.png), [balances: control jumps up](before-segment-balances.png) | [expenses](after-segment-expenses.png), [balances](after-segment-balances.png), [activity](after-segment-activity.png): control stays put |
| W12 Tap "Kabir hasn't joined yet" | [leaves for wa.me at once](before-invite-tap.png) | [sheet with **Resend invite on WhatsApp**](after-invite-tap.png) |
| W12 Tap the avatar stack | [nothing happens](before-avatars.png) | [Members, with the add-person step](after-members.png) |
| W13 New space | [Cancel / Create bar, no grabber](before-new-space.png) | [grabber, ✕, bottom **Create space**](after-new-space.png) |
| W14 Confirm repayment | [round Material chevron](before-confirm.png) | [shared glass back; a real tap returns to the loan](after-confirm.png) |

In the W5 capture, the second tap at the same point lands on the next
segment: Balances then Activity.

Not shown on the simulator: typing a number into Members. Keyboard input
can't be sent with HID taps here. Widget tests cover adding, refusing a
number already in the space, failing, and retrying with the same key.
