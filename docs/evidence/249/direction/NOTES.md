# Website v3 direction — #249

**Direction.** Light only, jade on ivory, marigold as a single highlight (the kicker dot and the story's progress rule). The hero, the sticky "How it works" story and the trust centre are new. The rest of the page is unchanged for now. Product panels put a real capture on a ruled surface, with one floating crop from a real screen. The trust centre has six ruled cells, each stating a fact already on the site.

**Motion.** There are two curves: `--ease-out: cubic-bezier(.22,1,.36,1)` and `--ease-spring: cubic-bezier(.34,1.4,.64,1)`. Timings are `--dur-fast` 160ms (hover), `--dur-base` 320ms, `--dur-reveal` 720ms and `--stagger` 70ms. Headline words rise in turn. The hero has scroll-linked parallax. The story crossfades three panels on a native view timeline, with an IntersectionObserver fallback. Blocks reveal on view. All motion uses transform and opacity, and reduced motion gives a static, complete page.

**Grid.** Twelve columns, at most 1200px wide, with a 24px gap (16px at 760px or less). Spacing follows a 4/8px scale. There are five type sizes: display, h2, h3, lede and small.

**Checks.** See `lighthouse-summary.json`: LCP is 2.56–2.63s simulated, against a 2.25s baseline.
