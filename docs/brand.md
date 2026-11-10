# Settlo brand

**Positioning:** Settlo keeps shared expenses and personal loans clear between people who know each other in India.

## People and promise

For Indian flatmates splitting rent and groceries, friends sharing trips, and people keeping track of money lent or borrowed. Speak to the relationship as well as the record: “Good friends. Clear balances.” is the landing-page expression. Settlo records and reconciles; the user's own UPI app moves the money.

## Voice

Warm, calm, precise. Write in en-IN: flatmates, rupees, instalments, mobile numbers. Use everyday situations and short sentences. Explain what happens next, especially when another person needs to confirm. State the availability plainly: iPhone only, TestFlight beta; Android later. Beta access is an email enquiry, not an immediate download or guaranteed invitation.

Do:
- Say “split expenses with flatmates”, “track money lent to friends”, and “settle up via UPI” where they describe the task.
- Distinguish a recorded payment from a confirmed one; a loan from a shared expense.
- Explain privacy limits, including the shared records retained after account deletion.
- Use actual app screens with labelled example balances.

Don't:
- Promise instant settlement, payment verification, debt recovery or bank-level security.
- Imply that Settlo lends money, processes payments, reads SMS payments or uploads contacts.
- Invent ratings, testimonials, user counts, store badges, prices or launch dates.
- Turn financial status into celebratory confetti, guilt, or judgement.

## Visual system

Source of truth: `packages/core/lib/theme/colors.dart`, `typography.dart`, `tokens.dart`; welcome art direction: `docs/decisions/2026-11-10-welcome-redesign.md`.

| Token | Value | Site use |
| --- | --- | --- |
| background | `#0A0B0D` | Page canvas |
| surface | `#15171A` | Cards and screen frames |
| surfaceRaised | `#1E2126` | Raised surfaces |
| textPrimary | `#F3F2EE` | Headings and body |
| textSecondary | `#9B9D9A` | Supporting copy |
| action | `#D8B36A` | Primary text links, brand mark and welcome-inspired arcs |
| welcomeAction | `#F2C77F` | Beta enquiry button |
| buttonBorder | white at 10% | Hairline separators |
| owedToYou / youOwe | `#5BD39B` / `#F0715C` | Money direction only, preserved within app imagery |
| type | Figtree 400 / 500 | All site copy, self-hosted TTFs from core assets |
| app amount type | IBM Plex Serif 500 | Preserved in app screenshots; not an extra web download |
| spacing | 8, 16, 24, 32, 40, 48px | Rhythm; 4px optical half-step |
| radius | 24px card / 16px button | Shared app and web shape language |
| touch target | at least 44px | Navigation and actions |

The website extends the app type scale for readable marketing headings (34–76px) and body copy (16–21px). Gold arcs frame the product; they are not badges or status indicators. The existing S mark remains intact. No stock photography, decorative financial graphs or synthetic product screens. Near-black is intentional in both system themes, as on Welcome. Animation is unnecessary; reduced motion disables smooth scrolling. Native HTML disclosure elements work without JavaScript.

## Regenerating imagery

Use one script for both real app images, the S mark, provenance manifest and 1200×630 social card:

```sh
python3 -m venv /tmp/settlo-images
/tmp/settlo-images/bin/pip install Pillow==13.0.0
git fetch origin pull/142/head:refs/remotes/origin/pr-142
/tmp/settlo-images/bin/python scripts/site-images.py --home-ref origin/pr-142
```

The script defaults to the reviewed PR #142 snapshot `b66bbb68b64e38286caea04ce06b2db4202fa18c`. Pass an updated fetched ref when that PR changes, or `--home-ref HEAD` after it merges. Welcome comes from this checkout's `auth_welcome_390x844_dark.png`; Home comes from the specified ref's `home_main_390x844_dark.png`. `site/images/sources.json` records the resolved commit, original dimensions and source hashes. The screenshots keep their full content; conversion to WebP does not reconstruct or retouch the UI. The social card uses bundled Figtree and the same home screen. Review both viewport screenshots after regeneration.

## Claim evidence

Read against the implementation at landing-page base `ca9ee2c84aac85feb4ec742c6b535faf83c9e9ac`:

| Claim | Source |
| --- | --- |
| Spaces, phone invitations and equal/exact/percent/shares splits | `docs/api.md` create_space/add_expense; `packages/local/lib/src/repositories.dart` |
| Loans and confirmed repayments | `packages/features/loans/lib/src/record_repayment_sheet.dart`, `repayment_decision.dart`; `docs/api.md` |
| UPI handoff, never payment processing | `packages/features/settle/lib/src/upi.dart`; `docs/adr/0011-url-launcher.md` |
| Confirm settle-ups | `packages/features/spaces/lib/src/confirm_settlement_screen.dart` |
| Offline saved records and queued writes | `packages/local/lib/src/repositories.dart`, `sync.dart`; `app/lib/main.dart` |
| Live Activity for pending settle-up, not loan repayment | `packages/platform/lib/src/live_activity.dart` |
| CSV and summary PDF / loan statements | `packages/features/profile/lib/src/export_sheet.dart`; `packages/features/loans/lib/src/statement_button.dart` |
| Mumbai hosting, no contacts upload, no tracking | `site/privacy/index.html` where/what/website; `docs/context-pack.md` |
| In-app Profile › Delete account takes effect at once and cannot be undone; email settlo@hellojosh.studio if unable to sign in; shared records remain with the other people | `packages/features/profile/lib/src/screens.dart` `_deleteAccount`; `packages/features/profile/lib/src/profile_repository.dart` → `delete_account`; `docs/api.md` account deletion; email fallback wording aligned with PR #143 |
| iPhone TestFlight beta; Android later; operator/contact | Issue #140 and owner assignment; no unsupported public installation link |

Privacy/support policy wording belongs to PR #143. This change only adjusts their document metadata; shared CSS restyles the content without rewriting it.
