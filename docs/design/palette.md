# SabkiJeb "Settle Check" palette

Dark surfaces were neutralized in #248. The owner follow-up maps green accents
and owed amounts to marigold, and pending to neutral grey with its clock cue.
Light roles are unchanged.

Brand: Deep forest #01381E · Pocket jade #01672D · Marigold #FEBD11 · Check ivory #FEF0CE

| Role | Light | Dark |
|---|---|---|
| App background | #FBF8EF | #000000 |
| Card surface | #FFFDF8 | #1C1C1E |
| Primary text | #18271F | #F7F2E8 |
| Secondary text | #50645A | #B8B8B8 |
| Primary action (button fill) | #01672D | #FEBD11 |
| Button label | #FEF0CE | #01381E |
| Decorative divider | #D8E0D8 | #48484A |
| Control outline | #708478 | #858585 |
| You're owed | #01672D | #FEBD11 |
| You owe | #934636 | #F2AB98 |
| Pending | #795309 | #B8B8B8 |
| Error | #A42E35 | #FF9CA3 |

Primary button text contrast: light 6.23:1, dark 7.88:1.

Palette illustration only; existing screen layouts and button shapes are retained.
The clock is the approved non-colour cue on existing pending lines.
Reference card ("Goa trip"): light = card surface with 1px divider-coloured border, green "Add expense" pill; dark = #1C1C1E card, marigold pill with deep-forest label; amounts in owed/owe colours; a "pending" line with a clock icon in the pending colour.

## Derived roles

- Raised inputs/secondary surfaces: light `#F6F1E5` (ivory tinted toward the app background); dark `#2C2C2E` (neutral charcoal).
- Highest surfaces, avatars, chip tracks and chart tracks: light `#E8EDDE` (ivory with a jade tint); dark `#3A3A3C` (neutral charcoal). Primary text sits on these fills.
- Selected chips and navigation pills use the primary action and button label pair. Both gradient endpoints are identical so the exact action colour stays intact. Unselected outlines use the control-outline role.
- Muted text uses secondary text, preserving AA contrast. Specular card edges use the divider; they do not introduce a second border colour.
- Glass is card surface at 60% light / 62% dark opacity; the fallback is 92%. Glass borders use the divider. Native UIKit receives the same ARGB action tint from Flutter; supplied artwork stays untinted.
- Home's net-position hero uses the ordinary card surface in each appearance. Its amount uses money direction, including the sign; neutral zero uses primary text. Decorative arcs use the action hue at low opacity, with theme-foreground highlights; they convey no status.
- Welcome's button uses the exact action/label pair, without colour-shifting gradient stops. Welcome follows the current appearance.
- Chart progress uses the brand accent over the highest surface. Labels and amounts remain semantic text/money roles; a progress value is not an amount owed.
- Pending confirmations use the pending role and clock imagery. Errors use the error role, including Material validation and custom error labels.
- Black translucent shadows, transparent widget layers, and white alpha-only shader masks are compositing primitives, not brand colours. Exported statement raster text uses the light primary-text role on paper. The Dynamic Island uses the dark palette because its system surface is black.

## Audit and verification

Audit `Color(0x...)`, computed `Color(...)`, and `Colors.*` throughout `packages/**/lib` and `app/lib`, plus Swift UIKit and the Live Activity extension. The app name, launcher icon, supplied in-app S artwork, and website are outside this change.

`packages/core/test/theme/contrast_test.dart` checks all declared text/background pairs at 4.5:1, including the exact primary button pair, owed/owe amounts, pending and errors on content surfaces. Divider borders are decorative; interactive control outlines use the separate supplied outline role.
