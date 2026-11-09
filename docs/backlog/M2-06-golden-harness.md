Golden harness and canvas reference renders at 390 and 360
area:qa,type:chore,agent:codex
M2 Design system and app shell
**Owner:** Principal QA

## Acceptance criteria
- [ ] Script renders every `design/canvas/*.dc.html` artboard to PNG at 390x844 (and a 360x800 reflow where the artboard allows) using headless Chrome; output in `design/reference/` (committed)
- [ ] Shared golden test helper: device sizes 390x844 and 360x800, both themes, fonts loaded, deterministic
- [ ] CI runs goldens on a pinned runner image so they are stable
- [ ] `docs/release.md` describes how a UI PR attaches app-vs-canvas comparisons

## Test plan
Helper used by one sample golden; a deliberate pixel change fails CI.
