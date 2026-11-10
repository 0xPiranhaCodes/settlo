# Owner-approved Home redesign

**Date:** 10 Nov 2026 · **Decided by:** Owner and manager

Home follows the supplied owner mock in both themes. Its net-position card is
always a dark fixed surface, with white net amounts and a soft warm top-right
glow plus the fine arc stroke. Home uses one background arc at bottom-right,
above the floating navigation; it does not reuse Welcome's top-right arc.

Gold remains reserved for primary actions, the Settlo mark, navigation and
directional arrows. Home's `homeGold` token is lighter in dark mode and darker
in light mode so gold text and icons retain contrast. The active navigation
pill uses the owner-approved `#926A30` to `#473419` gradient with white content.
Mint and coral remain available only through `MoneyTone` for money owed.

All amounts use Figtree with tabular figures. Hero amounts render the rupee
sign at 66% of the number size. IBM Plex Serif is no longer used by the app or
exports and its bundled asset is removed, amending ADR 0006.

The Home header exposes Notifications and Profile as 44pt controls. Help and
support lives in Profile and opens the existing support page, with an in-app
failure message when the platform cannot open it. Home pull-to-refresh reloads
both balances and its recent-activity preview.
