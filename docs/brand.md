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
| action | `#D8B36A` | Primary text links, the marketing S mark (site, social card, App Store page) and welcome-inspired arcs; never the in-app mark |
| welcomeAction | `#F2C77F` | Beta enquiry button |
| buttonBorder | white at 10% | Hairline separators |
| owedToYou / youOwe | `#5BD39B` / `#F0715C` | Money direction only, preserved within app imagery |
| type | Figtree 400 / 500 | All site copy, self-hosted TTFs from core assets |
| app amount type | IBM Plex Serif 500 | Preserved in app screenshots; not an extra web download |
| spacing | 8, 16, 24, 32, 40, 48px | Rhythm; 4px optical half-step |
| radius | 24px card / 16px button | Shared app and web shape language |
| touch target | at least 44px | Navigation and actions |
| wordmark | `SETTLO`, Figtree 500, tracked 0.08em | Header, footer and social card; the app's Home lockup (`packages/features/balances/lib/src/screens.dart`, `letterSpacing: 1.8`). Markup says “Settlo”; CSS uppercases it so screen readers say the name |

The website extends the app type scale for product headings (42–132px) and body copy (16–21px). Gold arcs frame the product; they are not badges or status indicators. The existing S mark remains intact. The gold S mark is marketing only: the website, the social card and the App Store page. Inside the app the mark is monochrome and follows the theme, ink in light mode and white in dark mode (`SettloMark` uses `textPrimary`); the app icon and launch screen are unchanged. No stock photography, decorative financial graphs or synthetic product screens. Steps that happen outside a captured app screen (the payment in the user's own UPI app, a settle-up awaiting confirmation) are typeset sketch cards in site styles, captioned as illustrations; they never imitate a named UPI app or Settlo's own UI. The landing page defaults to warm paper (#faf9f6), charcoal text (#17191b), and accessible muted gold links (#806025), with two near-black sections. The system dark preference restores the app palette throughout. Phones rise gently on native CSS view timelines; a small IntersectionObserver supplies the fallback. Reduced motion disables animations, transitions, smooth scrolling and sticky positioning. The landing page avoids eyebrow labels and slogan-with-full-stop headings; each section carries one real moment (the Goa trip, Flat 402, the loan to Arjun) shown with its app screen. Native HTML disclosure elements work without JavaScript.

## Regenerating imagery

Use one script for both real app images, the S mark, provenance manifest and 1200×630 social card:

```sh
python3 -m venv /tmp/settlo-images
/tmp/settlo-images/bin/pip install Pillow==13.0.0
git fetch origin main
/tmp/settlo-images/bin/python scripts/site-images.py --ref origin/main
/tmp/settlo-images/bin/python scripts/site-phones.py
```

`--ref` defaults to `HEAD`. The script exports five real screens from `app/test/goldens/*_390x844_dark.png` (Home, Goa trip settle-up, Flat 402 balances, loan detail and repayment confirmation) as lossless WebP. The page shows them at their real 390px width or smaller, so text stays crisp. `site/images/sources.json` records the resolved commit, original dimensions, source hashes and crop row. Screens that continue below a floating navigation bar are cropped at a blank gap under the last whole card, then given 24px of the screen's own background so the rounded frame clips nothing; no row or line of text is cut. Nothing is reconstructed or retouched. Re-check the crop rows in the script whenever those goldens change. The social card uses bundled Figtree and the same Home screen. Review both viewport screenshots after regeneration.

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

Each phone uses the full pinned 390×844 golden (not the older standalone crops), with one lossy WebP output: quality 80 for Home and 88 for the others. Hardware uses a uniform scale derived from the actual screen width and measured opening. Final downsampling uses the upright canvas as the reference for every angle: tilted canvases expand to 433px rather than shrinking the device into 390px. HTML dimensions reserve the exact bitmap ratio; paired CSS columns preserve the common physical scale. No artificial 2x assets are shipped. Home and repayment remain straight; the trip, flat and loan-detail images tilt. Native scroll motion adds at most 2 degrees temporarily within generous section spacing.
