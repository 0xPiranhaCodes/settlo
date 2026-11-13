# Dark palette audit

Scope includes the owner's [follow-up](https://github.com/0xPiranhaCodes/settlo/issues/248#issuecomment-6854358426): neutral surfaces, marigold owed amounts and accents, neutral pending text with existing cues. Light mode is unchanged.

Searched Dart production sources in `app/lib`, `packages/core/lib`, and every feature's `lib` for literal/computed `Color`, `Colors.green`, money tones, and fill/background use. Searched all Swift in `app/ios/Runner` and `app/ios/SettloWidgets` for UIKit/SwiftUI colours and fills.

- Cards, inputs, chips, selected rows, banners, sheets, Flutter glass and welcome artwork consume semantic tokens. No separate hard-coded green dark background was found in those consumers.
- `GlassButton.swift` uses native `.glass()` / `.gray()` and Flutter ARGB foreground/badge values; `NativeTabBar.swift` uses UIKit material and the Flutter action tint. Neither hard-codes a green fill.
- `SettleUpLiveActivity.swift` duplicated dark secondary/pending/track constants. These follow the neutral grey app roles in this change. Its clock label is retained.
- Disabled primary-button custom glyphs could retain forest `onAction` on a grey fill. The dark-only disabled foreground filter neutralizes explicit icon paint; a rendered-pixel test covers enabled/disabled and light/dark states.
- Enabled iOS and Material switch thumbs previously reused forest `onAction` as a fill. Dark thumbs now use neutral black; light thumbs are unchanged.
- Owed amounts use the shared money role. Pending clocks and labels in Home, Spaces, Loans and Activity remain in place; you-owe stays salmon and errors stay pink.
- Forest `onAction` / `onNavActive` is restricted to foreground labels/icons on marigold. Transparent layers, black shadows and white shader masks are neutral compositing primitives. Light-only green shadows and statement text on white paper remain unchanged.
- The supplied check/logo artwork is an explicit coordinator-confirmed brand exception; its green pixels remain unchanged, not reused as UI colours.
- No layout, navigation, data, launcher artwork or website styles changed.
