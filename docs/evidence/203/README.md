# #203: SabkiJeb name, app icon and in-app logo

Captured on 12 Nov 2026 on a dedicated iPhone 17 Pro simulator (iOS 26.1),
created for this task and deleted afterwards. The app is the #191 capture app
(`docs/evidence/191/glass_capture_app.dart.txt`, fakes, Home route, 3 unread).

## Files

- `ios26-springboard.png`: SpringBoard in dark (left) and light (right). The
  label reads SabkiJeb and the icon is the full-bleed logo, opaque RGB.
- `ios26-home.png`: Home in dark and light; `home-header.png` is the header
  close-up. The logo, clipped to a circle, sits in the native Liquid Glass
  circle where the S was. Recaptured after rebasing onto the #206 palette on
  a disposable iPhone 16 Plus simulator (iOS 26.1, deleted afterwards) with
  `integration_test/palette_app.dart` and `testPaletteEvidence`. The glass
  rim reads on `#000000` (rim 1.57:1); on `#FBF8EF` the glass circle stands
  out by its shadow, and the forest disk is 12.75:1 against the glass.
- `android-masks.png`: the adaptive icon as a launcher shows it, with the
  foreground over `#01351B` inside the 72dp viewport under circle, squircle
  and rounded-square masks, then the monochrome layer tinted like a themed
  icon under circle and squircle masks.
  No emulator was run for this change.

## Android adaptive foreground: cutout, not the scaled logo

The mark is lifted off the background with colour-to-alpha against the
sampled `#01351B`. Because alpha is solved against the same colour the
adaptive background uses, recompositing gives back the logo within 3/255 near
the mark (the script asserts this), so there is no dark halo or fringe. The
soft green glow is kept as partial alpha. The darker vignette in the logo's
corners is dropped, and only lighter pixels count away from the mark. The
whole cutout, glow included, fits the centred 66% safe circle (scale 0.598,
radius 0.445 of the source).

The monochrome layer is the solid check and pocket, without the glow:
`|pixel - background| > 100`, with enclosed holes in the translucent pocket
filled and the dark shadow slits between check and pocket kept.

## Share and export text (asserted in tests)

- Space invite (WhatsApp): `Hi, this is Sana. I added you to Flat 402 on SabkiJeb. Nothing is shown until you verify this number. <link>`
- Loan invite: `Hi, this is Sana. I recorded a loan between us on SabkiJeb. You will see it in SabkiJeb once you verify this number. <link>`
- Settle-up request: `Hi Priya, settling up Flat 402: please pay ₹2,100 to sana@okaxis on any UPI app. Sent from SabkiJeb.`
- UPI note: `SabkiJeb: Goa trip` (`tn=SabkiJeb%3A%20Goa%20trip`)
- PDF statements: wordmark `SabkiJeb`, creator `SabkiJeb`, footer `Made on this device from what you see in SabkiJeb. SabkiJeb is a record; it never holds or moves money.`
- Export files: `sabkijeb-<space>-expenses-<date>.csv`, `sabkijeb-<space>-summary-<date>.pdf`, `sabkijeb-loan-statement-<date>.pdf`
- Reminder notification title (iOS): `SabkiJeb`; Live Activity: `SabkiJeb · <space>`
