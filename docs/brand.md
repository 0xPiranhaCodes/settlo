# Settlo brand

**Positioning:** Settlo keeps shared expenses and personal loans clear between people who know each other in India.

App UI usage rules: [ui-guidelines.md](ui-guidelines.md).

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

### App dark palette (#248)

The app keeps a true-black canvas and neutral charcoal cards, inputs, chips,
sheets and glass backing. Green accents, including owed-to-you amounts, become
marigold in dark mode.
Pending uses neutral grey with its existing clock cue. Action and selected-navigation labels use neutral near-black `#111111`. Light-mode tokens are unchanged.

The supplied check/logo artwork is an explicit
brand exception: retain its original pixels and colours in both appearances;
never tint or redraw it as part of the UI palette.

| Role | Dark value |
| --- | --- |
| background | `#000000` |
| surface / surfaceRaised / surfaceHighest | `#1C1C1E` / `#2C2C2E` / `#3A3A3C` |
| hairline / specular / glassBorder | `#48484A` |
| buttonBorder | `#858585` |
| textPrimary | `#F7F2E8` |
| textSecondary / textMuted | `#B8B8B8` |
| glass / glassFallback | `#1C1C1E` at alpha `0x9E` / `0xEB` |
| action / welcomeAction / brandAccent / active navigation | `#FEBD11` |
| enabled switch thumb | `#000000` on marigold |
| onAction / onNavActive (text on marigold) | `#111111` |
| owedToYou / youOwe / pending / error | `#FEBD11` / `#F2AB98` / `#B8B8B8` / `#FF9CA3` |

Adjacent opaque surfaces have at least 1.2:1 luminance contrast. Secondary and
muted text clear WCAG AA 4.5:1 on all four levels; existing `ContrastPair` tests
cover the remaining permitted text pairs. Glass retains its previous alpha.

### Website palette

The following marketing values describe the website, not the app dark tokens.

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

The website extends the app type scale for product headings (42–132px) and body copy (16–21px). Gold arcs frame the product; they are not badges or status indicators. The existing S mark remains intact. The gold S mark is marketing only: the website, the social card and the App Store page. Inside the app the mark is monochrome and follows the theme, ink in light mode and white in dark mode (`SettloMark` uses `textPrimary`); the app icon and launch screen are unchanged. No stock photography, decorative financial graphs or synthetic product screens. Steps that happen outside a captured app screen (the payment in the user's own UPI app, a settle-up awaiting confirmation) are typeset sketch cards in site styles, captioned as illustrations; they never imitate a named UPI app or Settlo's own UI. The landing page defaults to warm paper (#faf9f6), charcoal text (#17191b), and accessible muted gold links (#806025), with two near-black sections. The site is light only (#249): a dark system preference does not change it, and `site-check.cjs` asserts that. Phones rise gently on native CSS view timelines; a small IntersectionObserver supplies the fallback. Reduced motion disables animations, transitions, smooth scrolling and sticky positioning. The landing page uses restrained gold eyebrow labels and short headings; each section carries one real moment (the Goa trip, Flat 402, the loan to Arjun) shown with its app screen. Native HTML disclosure elements work without JavaScript.

## Illustration (#242)

SabkiJeb illustrations are cut paper laid on a table: a few flat, hand-cut shapes, one ink line, one grain. They are hand-written SVG, authored by Claude in code; no stock, traced, generated or copied imagery. Simple, confident and specific beats busy. Every piece follows these rules:

- **One subject, one moment.** Each piece shows one everyday Indian scene through its objects: the Goa bill cut into shares, the shirt pocket (*jeb*) holding the record, the khata with today's entry, the chaiwala's carrier with the tab clipped on, a price tag snipped off. At most six objects. The story sits in the central square of a cover (x 262–938 of 1200), so square crops in cards and the blog list keep it; flanking props may crop.
- **No people.** Never faces, hands, figures or mascots. People are present through their things: one kulhad each, a pair of chappals, sunglasses.
- **Two views only.** Flat-lay from directly above, or straight elevation. No perspective, isometric or 3D.
- **Shapes.** Flat fills only: no gradients, outlines, glows or blurs. Paper is cut square with a 6-unit corner (4 on small parts); round things are true circles. Receipts tear with a 10-unit zigzag. Cut edges may run a few units off true, and objects rest at −10° to +10°; the focal object stays nearest to straight.
- **Line.** One ink line: 6 units, round caps and joins, `#18271f`. Ink appears only on paper, as writing rows (never real text or numerals) and fold lines. Thin objects (strings, wire, straws, straps) use the same 6–12-unit weight in forest. Stitching is a cream 4–5-unit dash (11–14 on, 9–12 off).
- **Units.** Covers are 1200×675 and spots 480×360, both shown at about half size, so ink reads at about 3 CSS px everywhere.
- **Shadow.** Lifted paper and objects cast one hard shadow: the same shape offset 8 right and 10 down, ink at 14%. Nothing sewn or printed casts a shadow.
- **Palette.** Forest `#01381e`, jade `#01672d`, cream `#fef0ce`, paper `#fffdf8`/`#f6f1e5`, ink `#18271f`, plus the steel `#708478` of scissor blades. Marigold `#febd11` appears once per piece, on the money or the moment (the coin, the newest entry, the blank tag, the stamp). The app's owed/owe colours are never used: illustrations do not show balance direction.
- **Money.** The ₹ is drawn as a forest stroke on a marigold coin, never typeset. No amounts, cards, banks or UPI apps.
- **Grain.** One `feTurbulence` noise (fractal, base frequency 0.85, two octaves) tinted ink at 16%. Covers lay it over the whole field; spots clip it to their shapes so the page shows through.
- **Light only (#249).** The website has no dark mode. SVGs carry no `prefers-color-scheme` styles, and every page declares `color-scheme: light`. Social cards are light too.
- **Budget and markup.** Each SVG at most 15 KB gzipped (current pieces are about 1 KB). Images carry width and height, `decoding="async"`, and `loading="lazy"` below the fold. Spots and covers are decorative (`alt=""`); every social card has descriptive `og:image:alt`.
- **Restraint.** Spots never replace or sit inside the real app captures. The landing page has two: the snipped price tag in Free and the chai carrier under the FAQ heading. Anything that does not add meaning is cut.

Sources: covers in `scripts/blog/covers/`, landing spots in `site/images/art/`, card-only art (privacy pocket, support envelope, terms, deletion eraser) in `scripts/cards/art/`.

### Social cards

Every page has a 1200×630 PNG card in `site/images/cards/` for `og:image` and `twitter:image` (`summary_large_image`). `node scripts/site-cards.cjs` (Playwright and Chromium, a local tool, not a site dependency) renders them from the SVG art, the post front matter and self-hosted Figtree, then records input and output hashes in `scripts/cards/manifest.json`. `python3 scripts/site-build.py --check`, and so `site-build-check.py` and `site-check.cjs`, rejects a changed cover, spot, post, font or card until the cards are re-rendered and committed. A new page needs an entry in the script's card list. The layout is fixed: wordmark top left, a jade kicker, the title in Figtree 500 sized to fit, `sabkijeb.app`, and the illustration in a 24px-radius panel on the right.

## Regenerating imagery

The opt-in marketing export shares the golden fixtures and screen builders. Run it from `app/`; it does not match or write CI golden PNGs and is not named `_test.dart`, so normal test discovery does not run it.

```sh
SITE_IMAGE_PYTHON=python scripts/site-build-images.sh
```

Use Pillow 13.0.0 with AVIF support. The single rebuild command always renders the current app widgets first, so a merged in-app mark/theme change is picked up automatically without editing screen pixels or reusing stale exports. The export renders 390×844 detail sources (1170×2532 pixels) and 430×932 phone displays (1290×2796 pixels), both directly from Flutter at devicePixelRatio 3 in `build/marketing/`. Phone exports supply 54px top and 34px bottom safe-area insets. The shared golden harness and all committed golden PNGs remain unchanged. `site-images.py` maintains the logo and golden provenance; `site-phones.py` consumes the separate 3x export for the actual page imagery. `sources.json` records both source hashes, the DPR, crop rectangles, output dimensions and encoding recipe.

Phone composites have 1x, 2x and 3x AVIF alternatives in `srcset`. The image budget is the total unique images selected by one page at each density, including all below-fold phone images, detail crops and the mark: at most 350 KiB at every density. Alternate density files are not fetched together, and pages never fetch the social cards. Crop images contain complete UI controls or cards, and are capped at their logical source widths to preserve 3x sharpness. No generated app UI or retyped screenshot text is used.

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
| In-app Profile › Delete account takes effect at once and cannot be undone; email support@sabkijeb.app if unable to sign in; shared records remain with the other people | `packages/features/profile/lib/src/screens.dart` `_deleteAccount`; `packages/features/profile/lib/src/profile_repository.dart` → `delete_account`; `docs/api.md` account deletion; email fallback wording aligned with PR #143 |
| iPhone TestFlight beta; Android later; operator/contact | Issue #140 and owner assignment; no unsupported public installation link |

Privacy/support policy wording is preserved from merged PR #143. Their `<main>` stays byte-identical apart from the SabkiJeb name and support address (#204), checked by `scripts/site-check.cjs`; the shared header, footer and CSS restyle the pages without rewriting the policy.

### Phone compositions

`site-phones.py` draws an illustrative device around the complete 430×932 Flutter display. Concentric rounded rectangles share a 52px display radius and 8px bezel, so the screen mask exactly matches the frame. The previous generated frame is retained only as historical source material in `scripts/phones/`, outside the published site; it is not consumed by the pipeline. PNG fallbacks round RGB to multiples of 3 (at most 1/255 off) to stay within the 150 KB image budget. The display aspect ratio matches the export exactly, without stretching, cropping, or filling spare rows.

Only illustrative system chrome (time, signal, battery, Dynamic Island and home indicator) is drawn in the reserved safe areas. App controls and text remain real Flutter pixels. The trip, flat and loan-detail frames tilt by ±3 degrees; Home and repayment remain upright. Every phone has one physical scale and 1x/2x/3x AVIF variants. The manifest records display geometry, export hashes and output dimensions; HTML reserves the exact canvas ratio and CSS uses the corresponding 430:390 tilted/upright widths.

The Goa story pins the complete phone beside three compact steps on wide screens, with its height bounded below the sticky nav. At tablet and phone widths the full-size phone flows above the steps, avoiding a sticky image taller than the viewport. Reduced motion removes sticky positioning and all animated transitions. The slim nav uses a solid background by default, enhances with backdrop-filter, and returns to solid under prefers-reduced-transparency.

### Feature tile evidence

- UPI: `packages/features/settle/lib/src/upi.dart` hands off to the user's own app; the recipient confirms separately.
- Reminders: `packages/features/loans/lib/src/remind_button.dart`, `packages/core/lib/supabase/reminders.dart` and the `remind_loan` SQL function enforce a 24-hour shared cooldown and recipient opt-out. Reminders are online-only.
- Offline: `packages/local/lib/src/repositories.dart` and `sync.dart` keep saved records and queue supported writes. Initial sign-in needs connectivity; the tile does not promise offline reminders or payments.
- Instalments: `packages/features/loans/lib/src/loan_detail.dart` renders the same schedule and outstanding amount shown in the tile; repayments count after confirmation.

## Website publication flags (#230 / #228)

The public site is still a buildless `site/` artifact. Edit
`scripts/site-index.template.html`, then run `python3 scripts/site-build.py` and
commit its generated `site/index.html`. `scripts/site-features.json` is the single flag
map, kept outside the published `site/` artifact; every future flag defaults to `false`. Disabled HTML is removed at build
time, including FAQ entries and comparison rows, rather than hidden with CSS.
The FAQ JSON-LD is generated from the surviving visible answers.

`site-serve.py` and `site-build-images.sh` run the builder; `site-check.cjs`
rejects stale generated output. The existing Pages workflow needs no change.
Run `python3 scripts/site-build-check.py` to check independent flags, combined
flags, dependency gates, schema generation and output freshness.

| Flag | Issue | Gated content |
| --- | --- | --- |
| `settle_link` | #213 | No-install and live-status cards, sample status feed, alternate app-needed FAQ |
| `person_qr` | #214 | Personal QR card and scan comparison row |
| `partial_payments` | #215 | Partial-payment card and Spaces pay-over-time point |
| `pay_by_dates` | #216 | Pay-by card |
| `reminder_tones` | #217 | Reminder-tone card (existing loan reminders remain visible) |
| `receipt_scan` | #220 | Receipt card and receipt-photo FAQ |
| `hindi_toggle` | #222 | Hindi FAQ; language preview also requires `partial_payments` |
| `widget` | #224 | Home Screen widget card |
| `guest_add` | #225 | Spaces web-entry point |
| `summary_card` | #226 | Shareable summary card |
| `spin` | #227 | Spin-to-pick card |
| `item_splits` | #219 | Item-level and tax/service comparison rows |
| `foreign_currency` | #221 | Currency-conversion FAQ |

The final two gates preserve the requested future comparison/FAQ content without
advertising unshipped features. Flip the relevant flag in the feature's shipping
PR and regenerate; verify the prepared copy against its final implementation.
All cards are free: no Pro labels, price switch or coming-soon claims. The
language preview requires both dependencies. Social handles are omitted.
Blog (#231) and Terms (#232) are published and linked from the shared navigation.

Original bill and conversation examples use fictional Neel, Tara and Dev and
explicitly distinguish recorded payments from confirmed receipt. The reference
site informed section order only. Existing real iOS capture assets are reused
unchanged; the profile crop contains `demo@upi`. No simulator was needed.
The final QR encodes exactly the existing beta CTA mailto URI:
`mailto:support@sabkijeb.app?subject=SabkiJeb%20TestFlight%20beta`.
It was generated locally with Python `qrcode` as an SVG with a four-module quiet
zone; it does not call a QR service or introduce third-party requests.

## Blog authoring and publication (#231)

Run `python3 scripts/site-build.py` after editing `scripts/blog/posts/*.md`,
`scripts/blog/covers/*.svg`, or `scripts/blog/page.template.html`. Commit the
sources and generated `site/blog/` pages and covers together. `site/blog/posts/`
was the proposed authoring path; sources instead live under `scripts/` because
Pages uploads **all** of `site/`, dereferencing symlinks. This keeps Markdown out
of the published artifact without changing the deployment workflow, just as
`scripts/site-features.json` stays outside it.

Each post starts with JSON front matter between `---` lines: `title`, `type`
(Announcement, Guide or Product update), ISO `date`, one-line `summary`, and
`cover` (the name of a source SVG without its extension). The filename supplies
the lowercase hyphenated slug. The dependency-free Markdown subset supports
paragraphs, `##` headings, `-` lists, `**strong**`, and links to root-relative
site URLs or `mailto:` addresses; raw HTML is escaped. Keep blank lines between
blocks. Unsupported heading/list syntax and unsafe links fail the build.

The builder reuses the rendered landing page header/footer, generates per-post
metadata and Article JSON-LD, and includes all public index pages in the sitemap.
Deleting a post source removes its generated page and unused cover on rebuild.
`site-build-check.py` checks metadata and sitemap coverage, mutates source, HTML
and cover fixtures to prove drift rejection, and proves deleted posts disappear.
`site-check.cjs` discovers all generated post routes and checks both themes at
360, 390, 768 and 1440px, including internal links, metadata and requests.

The three covers follow the Illustration rules above. Blog styling
uses the current shared theme tokens and self-hosted Figtree, with no script,
third-party asset or animation required. Support links to Blog only in its header;
its guarded main and privacy's guarded main remain byte-identical.

To update the product log, add a dated heading and shipped changes to
`scripts/blog/posts/whats-new.md`; change the front-matter date only if publishing
it as a new edition. Keep planned M7 features out until implementation and release
status support the claim. The launch guide is grounded in
`packages/features/expenses/lib/src/add_expense_sheet.dart` (four split types),
`packages/features/spaces/lib/src/space_detail.dart` (simplified settlement),
`packages/features/settle/lib/src/upi.dart` (handoff),
`packages/features/spaces/lib/src/confirm_settlement_screen.dart` (confirmation),
and `packages/features/loans/lib/src/loan_detail.dart` (instalments and repayments).
Availability follows README; deletion follows Profile, the privacy policy and the
published deletion page. Owner copy approval is required before merge.
