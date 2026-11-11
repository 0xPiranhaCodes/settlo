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
| wordmark | `SETTLO`, Figtree 500, tracked 0.08em | Header, footer and social card; the app's Home lockup (`packages/features/balances/lib/src/screens.dart`, `letterSpacing: 1.8`). Markup says “Settlo”; CSS uppercases it so screen readers say the name |

The website extends the app type scale for product headings (42–132px) and body copy (16–21px). Gold arcs frame the product; they are not badges or status indicators. The existing S mark remains intact. No stock photography, decorative financial graphs or synthetic product screens. Steps that happen outside a captured app screen (the payment in the user's own UPI app, a settle-up awaiting confirmation) are typeset sketch cards in site styles, captioned as illustrations; they never imitate a named UPI app or Settlo's own UI. The landing page defaults to warm paper (#faf9f6), charcoal text (#17191b), and accessible muted gold links (#806025), with two near-black sections. The system dark preference restores the app palette throughout. Phones rise gently on native CSS view timelines; a small IntersectionObserver supplies the fallback. Reduced motion disables animations, transitions, smooth scrolling and sticky positioning. The landing page uses restrained gold eyebrow labels and short headings; each section carries one real moment (the Goa trip, Flat 402, the loan to Arjun) shown with its app screen. Native HTML disclosure elements work without JavaScript.

## Regenerating imagery

The opt-in marketing export shares the golden fixtures and screen builders. Run it from `app/`; it does not match or write CI golden PNGs and is not named `_test.dart`, so normal test discovery does not run it.

```sh
(cd app && flutter test test/marketing_export.dart)
python scripts/site-images.py --ref HEAD
python scripts/site-phones.py
```

Use Pillow 13.0.0 with AVIF support. The export renders a 390×844 logical viewport at devicePixelRatio 3 and captures 1170×2532 pixels directly from Flutter, in `build/marketing/`. The shared golden harness and all committed golden PNGs remain unchanged. `site-images.py` maintains the logo, social card and golden provenance; `site-phones.py` consumes the separate 3x export for the actual page imagery. `sources.json` records both source hashes, the DPR, crop rectangles, output dimensions and encoding recipe.

Phone composites have 1x, 2x and 3x AVIF alternatives in `srcset`. The image budget is the total unique images selected by one page at each density, including all below-fold phone images, detail crops and the mark: at most 350 KiB at every density. Alternate density files and the social sharing card are not fetched together. Crop images contain complete UI controls or cards, and are capped at their logical source widths to preserve 3x sharpness. No generated app UI or retyped screenshot text is used.

## Claim evidence

Read against the implementation at landing-page base `0f610060b640b23f0a7a7b73f7783a140e70680b`:

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

Privacy/support policy wording is preserved from merged PR #143. Their `<main>` stays byte-identical (checked by `scripts/site-check.cjs`); the shared header, footer and CSS restyle the pages without rewriting the policy.

### Phone compositions

`site-phones.py` wraps the approved screen crops in the committed generic studio frame (`site/images/device/studio-frame.png`). The frame was generated with the built-in image-generation tool; its complete prompt is beside it. No app screen was sent to the model. The recipe records the measured opening, hardware source hash, rotations and output dimensions in `sources.json`. It scales hardware uniformly around each full golden, pastes the real screen, then rotates the complete composition by 0 or ±3 degrees. A 24px corner mask clips blank screen corners only. Generated hardware is desaturated to remove coloured edge fringes; the screen is never colour-graded.

Each phone uses the full 3x marketing export, with a common physical scale. Hardware is scaled uniformly around the screen. Real screen pixels are composited last; only geometric resampling and AVIF encoding follow. The trip, flat and loan-detail frames tilt by ±3 degrees. Home and repayment remain upright. The manifest gives each logical canvas size; HTML reserves that exact ratio.

The Goa story pins the complete phone beside three compact steps on wide screens, with its height bounded below the sticky nav. At tablet and phone widths the full-size phone flows above the steps, avoiding a sticky image taller than the viewport. Reduced motion removes sticky positioning and all animated transitions. The slim nav uses a solid background by default, enhances with backdrop-filter, and returns to solid under prefers-reduced-transparency.

### Feature tile evidence

- UPI: `packages/features/settle/lib/src/upi.dart` hands off to the user's own app; the recipient confirms separately.
- Reminders: `packages/features/loans/lib/src/remind_button.dart`, `packages/core/lib/supabase/reminders.dart` and the `remind_loan` SQL function enforce a 24-hour shared cooldown and recipient opt-out. Reminders are online-only.
- Offline: `packages/local/lib/src/repositories.dart` and `sync.dart` keep saved records and queue supported writes. Initial sign-in needs connectivity; the tile does not promise offline reminders or payments.
- Instalments: `packages/features/loans/lib/src/loan_detail.dart` renders the same schedule and outstanding amount shown in the tile; repayments count after confirmation.
