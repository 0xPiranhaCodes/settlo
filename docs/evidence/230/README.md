# #230 / #228 — landing flow, trust and deletion

## Result

The reference at https://bharpai.app/ was read for section order only. Copy,
bill illustration and fictional conversation are original; all phone/detail
images are the existing real SabkiJeb iOS captures, unchanged. The current beta
mailto flow is used for every CTA and the locally generated, decoded QR.

`before/` contains full-page 390px and 1440px light/dark captures of origin/main.
`after/` contains the same four views, plus the deletion page in both themes.
All captures use reduced motion so every section is legible. Chrome's GPU
wrapped the bottom of the 16,563px mobile image; final screenshots use
`--disable-gpu` to preserve the actual footer. No image content was redrawn.

The page order is nav → hero/bill → static benefit strip → awkward story →
existing how-it-works walkthrough → chat and live feature cards → gated language
preview → features grid → comparison → gated sample feed → old-way scroll story
→ Spaces → personal loans → free → trust → FAQ → beta CTA/QR → footer.

## Gated content (all OFF)

| Flag | Issue | Content prepared but absent from public HTML |
| --- | --- | --- |
| `settle_link` | #213 | No-install card, live-status card, sample feed, replacement app-needed FAQ |
| `person_qr` | #214 | Personal QR card, scan comparison row |
| `partial_payments` | #215 | Partial-payment card, Spaces pay-over-time point |
| `pay_by_dates` | #216 | Due-date card |
| `reminder_tones` | #217 | Tone card |
| `receipt_scan` | #220 | Receipt card and photo FAQ |
| `hindi_toggle` | #222 | Hindi FAQ, language preview (also requires partial payments) |
| `widget` | #224 | Home Screen widget card |
| `guest_add` | #225 | Spaces web-entry point |
| `summary_card` | #226 | Shareable summary card |
| `spin` | #227 | Spin-to-pick card |
| `item_splits` | #219 | Item and tax/service comparison rows |
| `foreign_currency` | #221 | Foreign-currency FAQ |

The last two additional flags cover the future rows/questions explicitly named
in #230. Social handles are omitted; Blog/Terms await #231/#232 with comments.
No Pro badge, billing switch, invented endorsement or coming-soon promotion.

## Verification

- `python3 scripts/site-build-check.py`: passed default, each flag independently,
  all flags on, language dependency, FAQ schema generation and committed-output
  freshness. Unknown flags fail closed. See `build-check.txt`.
- `site-check.cjs`: passed 360/390/768/1440 light/dark, including deletion page,
  no horizontal overflow or external resource requests; FAQ/schema parity,
  phone geometry, native/fallback/reduced motion and density checks. See
  `browser.json`, `motion.json`, `density.json`.
- `site-images-ready-check.cjs`: passed 15 fresh no-JS density contexts and the
  corrupt-image negative control (`images-ready.txt`).
- Axe WCAG 2 A/AA and 2.1 AA: no violations on landing/deletion in light or dark
  (`axe.json`). Lighthouse also checks active-motion contrast: story text stays
  fully opaque throughout its translation animation.
- Mobile Lighthouse: landing **99 performance / 100 accessibility / 100 best
  practices / 100 SEO**; deletion **100 / 100 / 100 / 100**. Full local reports
  are included; localhost with simulated mobile throttling, not a production
  measurement. The first run found animated-text contrast and heading order;
  both were fixed before these reports. No host-load exception was needed.
- All-flags browser preview: 360/1440, both themes, reduced/normal motion;
  no overflow, Hindi radio interaction works, feed pause works, and reduced
  motion removes feed animation (`flag-preview.json`).
- Rendered QR decoded to
  `mailto:support@sabkijeb.app?subject=SabkiJeb%20TestFlight%20beta`, exactly the
  CTA href. No external QR service.
- Visual inspection covered both widths/themes and deletion. Existing captures
  retain `demo@upi`; no simulator was created. `.github` is unchanged.

Local reproduction (with Playwright installed and Chrome available):

```sh
python3 scripts/site-build.py
python3 scripts/site-build-check.py
python3 scripts/site-serve.py --port 8930
# In another terminal:
SITE_CHECK_URL=http://127.0.0.1:8930/ node scripts/site-check.cjs
SITE_CHECK_URL=http://127.0.0.1:8930/ node scripts/site-images-ready-check.cjs
```

## Claim evidence

- README: iPhone TestFlight beta, UPI intent, manual confirmation, Android later.
- `packages/features/expenses/lib/src/add_expense_sheet.dart`: equal/exact/
  percent/share splits.
- `packages/features/settle/lib/src/upi.dart`, `screens.dart`, `settle_sheet.dart`:
  own-app UPI flow and settlement recording.
- `packages/features/loans/lib/src/loan_detail.dart`, `remind_button.dart`,
  `statement_button.dart`: instalments, confirmation, reminders and statements.
- `packages/features/profile/lib/src/screens.dart`, `export_sheet.dart`:
  export, appearance and destructive deletion confirmation.
- `packages/local/lib/src/sync.dart`: local queue/sync behavior.
- Existing privacy deletion section: retained shared history, anonymised profile,
  provider retention, email fallback and completion within 30 days.

Phone authentication does require entering a verification code in the app. The
trust copy therefore explains that support never asks users to send an OTP,
PIN or bank details, without pretending phone authentication has no OTP step.
