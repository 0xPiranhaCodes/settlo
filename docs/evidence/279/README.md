# Design audit evidence — issue #279

Baseline: `6a928eb1b177598c1cf1cecd4ebfae40cfa2e324`. See the [scored audit](../../audits/design-2026-11-14.md) for verdicts, clauses, coverage limits and fix ownership.

## Root-tab matrix

All images are original simulator framebuffer captures at device resolution. `200` in filenames means iOS AX2 (`accessibility-large`, approximately 1.94× body), not an injected exact 2× scale.

| Device / tab | Light 100% | Dark 100% | Light AX2 | Dark AX2 |
|---|---|---|---|---|
| 16 / home | [capture](16-light-home.png) | [capture](16-dark-home.png) | [capture](16-light-200-home.png) | [capture](16-dark-200-home.png) |
| 16 / spaces | [capture](16-light-spaces.png) | [capture](16-dark-spaces.png) | [capture](16-light-200-spaces.png) | [capture](16-dark-200-spaces.png) |
| 16 / loans | [capture](16-light-loans.png) | [capture](16-dark-loans.png) | [capture](16-light-200-loans.png) | [capture](16-dark-200-loans.png) |
| 16 / activity | [capture](16-light-activity.png) | [capture](16-dark-activity.png) | [capture](16-light-200-activity.png) | [capture](16-dark-200-activity.png) |
| se / home | [capture](se-light-home.png) | [capture](se-dark-home.png) | [capture](se-light-200-home.png) | [capture](se-dark-200-home.png) |
| se / spaces | [capture](se-light-spaces.png) | [capture](se-dark-spaces.png) | [capture](se-light-200-spaces.png) | [capture](se-dark-200-spaces.png) |
| se / loans | [capture](se-light-loans.png) | [capture](se-dark-loans.png) | [capture](se-light-200-loans.png) | [capture](se-dark-200-loans.png) |
| se / activity | [capture](se-light-activity.png) | [capture](se-dark-activity.png) | [capture](se-light-200-activity.png) | [capture](se-dark-200-activity.png) |

## Reproduction and validation

- Main and auth fixture builds: [build.log](build.log), [auth-build.log](auth-build.log).
- Core contrast: `cd packages/core && flutter test test/theme/contrast_test.dart` — [91 passed](contrast.log).
- `flutter test test/widgets/pressable_test.dart test/widgets/glass_test.dart test/widgets/liquid_glass_test.dart` — [19 passed](accessibility-tests.log).
- HID: compile the existing `docs/evidence/188/simtouch.m`; all commands target the audit-owned UDIDs from the report. Scratch capture scripts and unredacted originals stay untracked in this worktree.
- Native flags: [probe source](accessibility-state.m), [Reduce Transparency](reduce-transparency-state.txt), [Increase Contrast](increase-contrast-state.txt), [Reduce Motion](reduce-motion-state.txt), [combined](combined-state.txt). Compile the probe for `arm64-apple-ios26.1-simulator` against Foundation/UIKit and execute with `simctl spawn <owned UDID> <probe>`. These are system values, not a claim that every Flutter widget consumes the preference.
- [Reduce Motion recording](reduce-motion.mp4) was recaptured after app relaunch and inspected as a 10 fps contact sheet. The dismissal visibly moves; no frame-exact duration is claimed. The video contains only fixture Home and the space picker, with no phone-number region.
- [Simulator deletion evidence](simulator-cleanup.txt): both audit UDIDs are absent; no other devices were modified.

## Privacy and evidence review

Every captured UI state was visually reviewed during the walkthrough; phone-bearing captures were reviewed again after masking. OCR at PSM 11 located phone/profile/invite regions; a PSM 6 rescan and visual review supplemented it. The scrolled OTP number was misread as letters by OCR and was masked manually. Opaque grey boxes remove phone numbers, hints and suffixes, including synthetic data. [redactions.json](redactions.json) records final pixel rectangles, not the underlying text. No unredacted original or OCR transcript is committed.

The evidence is not an independent live-service, VoiceOver, hardware-haptic or full Cartesian matrix certification. Consult the report coverage table before relying on a Pass.

## Capture inventory

99 stills; filenames encode device, appearance, text setting when AX2, and visible state. States without `200` use 100% unless the report explicitly identifies the alert inherited from an AX2 flow.

| Capture | Dimensions |
|---|---|
| [16-dark-200-activity](16-dark-200-activity.png) | 1179×2556 |
| [16-dark-200-add-expense](16-dark-200-add-expense.png) | 1179×2556 |
| [16-dark-200-home](16-dark-200-home.png) | 1179×2556 |
| [16-dark-200-loans](16-dark-200-loans.png) | 1179×2556 |
| [16-dark-200-spaces](16-dark-200-spaces.png) | 1179×2556 |
| [16-dark-200-split](16-dark-200-split.png) | 1179×2556 |
| [16-dark-200-welcome](16-dark-200-welcome.png) | 1179×2556 |
| [16-dark-accessibility-combined](16-dark-accessibility-combined.png) | 1179×2556 |
| [16-dark-activity](16-dark-activity.png) | 1179×2556 |
| [16-dark-add-expense](16-dark-add-expense.png) | 1179×2556 |
| [16-dark-date-picker](16-dark-date-picker.png) | 1179×2556 |
| [16-dark-discard](16-dark-discard.png) | 1179×2556 |
| [16-dark-home](16-dark-home.png) | 1179×2556 |
| [16-dark-loans](16-dark-loans.png) | 1179×2556 |
| [16-dark-spaces](16-dark-spaces.png) | 1179×2556 |
| [16-dark-welcome](16-dark-welcome.png) | 1179×2556 |
| [16-light-200-activity](16-light-200-activity.png) | 1179×2556 |
| [16-light-200-home](16-light-200-home.png) | 1179×2556 |
| [16-light-200-loans](16-light-200-loans.png) | 1179×2556 |
| [16-light-200-spaces](16-light-200-spaces.png) | 1179×2556 |
| [16-light-200-welcome](16-light-200-welcome.png) | 1179×2556 |
| [16-light-activity](16-light-activity.png) | 1179×2556 |
| [16-light-add-expense](16-light-add-expense.png) | 1179×2556 |
| [16-light-appearance](16-light-appearance.png) | 1179×2556 |
| [16-light-confirm-read-only](16-light-confirm-read-only.png) | 1179×2556 |
| [16-light-confirm-repayment](16-light-confirm-repayment.png) | 1179×2556 |
| [16-light-date-picker](16-light-date-picker.png) | 1179×2556 |
| [16-light-delete-account](16-light-delete-account.png) | 1179×2556 |
| [16-light-discard](16-light-discard.png) | 1179×2556 |
| [16-light-export](16-light-export.png) | 1179×2556 |
| [16-light-home](16-light-home.png) | 1179×2556 |
| [16-light-increase-contrast-scrolled](16-light-increase-contrast-scrolled.png) | 1179×2556 |
| [16-light-loans](16-light-loans.png) | 1179×2556 |
| [16-light-members](16-light-members.png) | 1179×2556 |
| [16-light-profile-bottom](16-light-profile-bottom.png) | 1179×2556 |
| [16-light-profile](16-light-profile.png) | 1179×2556 |
| [16-light-reduce-motion](16-light-reduce-motion.png) | 1179×2556 |
| [16-light-reduce-transparency-scrolled](16-light-reduce-transparency-scrolled.png) | 1179×2556 |
| [16-light-reduce-transparency](16-light-reduce-transparency.png) | 1179×2556 |
| [16-light-settle-confirm](16-light-settle-confirm.png) | 1179×2556 |
| [16-light-settle-payment](16-light-settle-payment.png) | 1179×2556 |
| [16-light-settle](16-light-settle.png) | 1179×2556 |
| [16-light-space-activity](16-light-space-activity.png) | 1179×2556 |
| [16-light-space-balances](16-light-space-balances.png) | 1179×2556 |
| [16-light-space-detail](16-light-space-detail.png) | 1179×2556 |
| [16-light-spaces](16-light-spaces.png) | 1179×2556 |
| [16-light-split-exact](16-light-split-exact.png) | 1179×2556 |
| [16-light-split-percent](16-light-split-percent.png) | 1179×2556 |
| [16-light-split-shares](16-light-split-shares.png) | 1179×2556 |
| [16-light-welcome](16-light-welcome.png) | 1179×2556 |
| [se-dark-200-activity](se-dark-200-activity.png) | 750×1334 |
| [se-dark-200-create-space-bottom](se-dark-200-create-space-bottom.png) | 750×1334 |
| [se-dark-200-create-space](se-dark-200-create-space.png) | 750×1334 |
| [se-dark-200-home](se-dark-200-home.png) | 750×1334 |
| [se-dark-200-loans](se-dark-200-loans.png) | 750×1334 |
| [se-dark-200-otp](se-dark-200-otp.png) | 750×1334 |
| [se-dark-200-phone](se-dark-200-phone.png) | 750×1334 |
| [se-dark-200-repayments-bottom](se-dark-200-repayments-bottom.png) | 750×1334 |
| [se-dark-200-repayments](se-dark-200-repayments.png) | 750×1334 |
| [se-dark-200-spaces](se-dark-200-spaces.png) | 750×1334 |
| [se-dark-200-welcome](se-dark-200-welcome.png) | 750×1334 |
| [se-dark-activity](se-dark-activity.png) | 750×1334 |
| [se-dark-home](se-dark-home.png) | 750×1334 |
| [se-dark-invites](se-dark-invites.png) | 750×1334 |
| [se-dark-loan-detail](se-dark-loan-detail.png) | 750×1334 |
| [se-dark-loan-repayments](se-dark-loan-repayments.png) | 750×1334 |
| [se-dark-loans](se-dark-loans.png) | 750×1334 |
| [se-dark-otp](se-dark-otp.png) | 750×1334 |
| [se-dark-phone-keyboard](se-dark-phone-keyboard.png) | 750×1334 |
| [se-dark-resend-invite](se-dark-resend-invite.png) | 750×1334 |
| [se-dark-spaces](se-dark-spaces.png) | 750×1334 |
| [se-dark-statement](se-dark-statement.png) | 750×1334 |
| [se-light-200-activity](se-light-200-activity.png) | 750×1334 |
| [se-light-200-add-expense](se-light-200-add-expense.png) | 750×1334 |
| [se-light-200-home](se-light-200-home.png) | 750×1334 |
| [se-light-200-loans](se-light-200-loans.png) | 750×1334 |
| [se-light-200-new-loan-action](se-light-200-new-loan-action.png) | 750×1334 |
| [se-light-200-new-loan-bottom](se-light-200-new-loan-bottom.png) | 750×1334 |
| [se-light-200-otp-scrolled](se-light-200-otp-scrolled.png) | 750×1334 |
| [se-light-200-otp-top](se-light-200-otp-top.png) | 750×1334 |
| [se-light-200-otp](se-light-200-otp.png) | 750×1334 |
| [se-light-200-spaces](se-light-200-spaces.png) | 750×1334 |
| [se-light-200-split](se-light-200-split.png) | 750×1334 |
| [se-light-200-welcome](se-light-200-welcome.png) | 750×1334 |
| [se-light-activity](se-light-activity.png) | 750×1334 |
| [se-light-add-expense](se-light-add-expense.png) | 750×1334 |
| [se-light-create-space](se-light-create-space.png) | 750×1334 |
| [se-light-home](se-light-home.png) | 750×1334 |
| [se-light-loans](se-light-loans.png) | 750×1334 |
| [se-light-new-loan-bottom](se-light-new-loan-bottom.png) | 750×1334 |
| [se-light-new-loan](se-light-new-loan.png) | 750×1334 |
| [se-light-otp-unfocused](se-light-otp-unfocused.png) | 750×1334 |
| [se-light-otp](se-light-otp.png) | 750×1334 |
| [se-light-settle](se-light-settle.png) | 750×1334 |
| [se-light-space-detail](se-light-space-detail.png) | 750×1334 |
| [se-light-spaces](se-light-spaces.png) | 750×1334 |
| [se-light-welcome](se-light-welcome.png) | 750×1334 |
| [settings-display](settings-display.png) | 1179×2556 |
| [settings-transparency-enabled](settings-transparency-enabled.png) | 1179×2556 |
