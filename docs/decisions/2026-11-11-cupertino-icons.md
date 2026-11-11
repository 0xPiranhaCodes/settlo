# Add cupertino_icons for iOS system actions

**Date:** 11 Nov 2026 · **Decided by:** Manager · **Status:** Accepted

## Context
The HIG expects system actions such as back, share and add to use the
system glyphs (sf-symbols). Settlo draws every icon as a custom line glyph.
Flutter's Cupertino widgets, such as the back chevron in
`CupertinoSliverNavigationBar`, draw from the `CupertinoIcons` font, which
ships in the `cupertino_icons` package; without it they render a blank box.
ADR 0005 requires an ADR for a new dependency.

## Decision
Add `cupertino_icons` (`^2.0.0`, MIT, a font with no native code) to
`settlo_core`, the package whose widgets draw it. Use it only for system
actions: back, share, more, add, delete and checkmark. Keep Settlo's custom
glyphs for brand concepts (space kinds, the loan ring) and the tab icons.

Alternatives considered: real SF Symbols through a native view or image
channel (rejected for now: platform-view cost for small glyphs and no
Android story); drawing the system glyphs by hand (rejected: they would
drift from Apple's shapes).

## Consequences
- The font is 258 KB; release builds tree-shake it to the glyphs used.
- The glyphs look like SF Symbols but are not them, so they do not follow
  the system weight or Bold Text. Real SF Symbols stay a possible follow-up.
- #158 PR 1 uses it for the native back chevron; PR 2 extends it to the
  other system actions.
