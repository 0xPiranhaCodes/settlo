# Dark palette audit

Scope includes the owner's [follow-up](https://github.com/0xPiranhaCodes/settlo/issues/248#issuecomment-6854358426): neutral surfaces, marigold owed amounts and accents, neutral pending text with existing cues. Light mode is unchanged.

Searched Dart production sources in `app/lib`, `packages/core/lib`, and every feature's `lib` for literal/computed `Color`, `Colors.green`, money tones, and fill/background use. Searched all Swift in `app/ios/Runner` and `app/ios/SettloWidgets` for UIKit/SwiftUI colours and fills.

- Cards, inputs, chips, selected rows, banners, sheets, Flutter glass and welcome artwork consume semantic tokens. No separate hard-coded green dark background was found in those consumers.
- `GlassButton.swift` uses native `.glass()` / `.gray()` and Flutter ARGB foreground/badge values; `NativeTabBar.swift` uses UIKit material and the Flutter action tint. Neither hard-codes a green fill.
- `SettleUpLiveActivity.swift` duplicated dark secondary/pending/track constants. These follow the neutral grey app roles in this change. Its clock label is retained.
- Disabled primary-button custom glyphs could retain forest `onAction` on a grey fill. The dark-only disabled foreground filter neutralizes explicit icon paint; a rendered-pixel test covers enabled/disabled and light/dark states.
- Enabled iOS and Material switch thumbs previously reused forest `onAction` as a fill. Dark thumbs now use neutral black; light thumbs are unchanged.
- Owed amounts use the shared money role. Pending clocks and labels in Home, Spaces, Loans and Activity remain in place; you-owe stays salmon and errors stay pink.
- Dark `onAction` / `onNavActive` and Swift `Palette.onAction` are neutral `#111111`, including Pay and GlassButton badge text. Transparent layers, black shadows and white shader masks are neutral compositing primitives. Light-only green shadows and statement text on white paper remain unchanged.
- The supplied check/logo artwork is an explicit coordinator-confirmed brand exception; its green pixels remain unchanged, not reused as UI colours.
- Scheduled Home/Loans subtitles retain “you lent” / “you borrowed”, including missing-date Home rows. Navigation, data, launcher artwork and website styles are unchanged.

## Colour-independent money direction

`check-tritanopia.py` reproduces Machado 2009 severity-1 tritanopia using the
[authors’ matrix table](https://www.inf.ufrgs.br/~oliveira/pubs_files/CVD_Simulation/CVD_Simulation.html).
Marigold/salmon CIE76 distance is **7.02** after linear-RGB simulation and gamut
clipping: the pair remains too close to rely on hue alone. Neutral `#111111`
on marigold is **11.24:1**, above AA.

Audited all owed/you-owe money-role consumers:
- Home net: signed amount and owed/owe caption; stats: “You are owed” / “You owe”.
- Home space rows and Spaces list: signed amounts; list also has direction text.
- Space balance header: “YOU ARE OWED” / “YOU OWE”.
- Settle rows: “You pay …” / “… pays you”; sheet also names the payer.
- Loan detail: “Outstanding” / “You owe” headings distinguish the two views.
- Home loan rows and Loans list: direction words now remain at the beginning of
  scheduled subtitles, so truncation cannot discard them. Both directions are
  asserted in each screen’s widget tests; Home also checks spoken semantics.

These are simulation and UI regression checks, not colour-vision user testing.
