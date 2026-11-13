# Study notes: what makes a fintech or SaaS site feel enterprise

These notes come from Stripe, Mercury and Linear (plus Ramp), each loaded in real Chrome at 390 and 1440 on 2026-11-13. Computed styles were sampled with Playwright. Nothing was copied, and none of their screenshots are committed.

- **One easing, used everywhere.** Stripe sets almost every transition (466 elements) to `cubic-bezier(.25,1,.5,1)` at 300ms. Mercury uses `cubic-bezier(0,0,.2,1)` at 300ms. The consistency matters more than which curve is chosen.
- **Two speeds.** Hover feedback runs at 100–160ms; Linear uses 100ms. Entrances run at 700–800ms on a softer curve: Linear `cubic-bezier(.32,.72,0,1)` at 700ms, Stripe `cubic-bezier(.165,.84,.44,1)` at 800ms.
- **Few type sizes.** Mercury uses 8–10 distinct sizes on a page and Ramp 11–12, mostly 12–18px body sizes plus one or two display sizes. Headlines have a single medium-to-light weight and slightly negative tracking: Linear is −0.022em, Stripe −0.02em at weight 300.
- **Fixed, visible containers.** Containers sit at 1266–1440px. Stripe draws hairline rails at the container edges and full-width rules between bands, so the grid itself becomes part of the look.
- **Restrained headlines.** Desktop H1s are 48–64px and H2s 42–48px; on mobile, H1s are 34–40px. They never fill the viewport.
- **Product over decoration.** Real UI panels are cropped and layered, and each section has one idea. Colour comes from the product rather than ornaments.
- **Entrances never hide meaning for long.** Linear's headline blurs and fades in under a second, and the content is never gated behind scroll.
