# Issue 145 design audit and test plan

The shared screen edge is 20 logical pixels. The coordinator approved a single
mock-fidelity exception: Welcome retains its 24px inset and warm action shadow.
Colours, the Figtree family, routes, keys, providers and mutation guards stay intact.
The owner-approved global type ramp changes sizes and permits Home/Welcome to grow.

| Area | Findings | Refinement |
| --- | --- | --- |
| Core | Independent press effects, heavy single floating shadow, no shared motion scale | Shared 150ms press / 200ms panel motion, Reduce Motion, layered floating shadow and minimum targets |
| Welcome | Approved composition with custom action feedback | Preserve composition, name the inset exception, share motion vocabulary |
| Phone / OTP / Join | 24px body edge differs from 20px header; custom tap regions | Align at 20px, shared feedback and minimum hit regions |
| Home | Approved composition; separate custom press implementation | Preserve resting layout and use shared pressable |
| Spaces list / empty | Mixed 14/18/22px internal spacing and direct InkWell rows | 8px rhythm, uniform interactive cards |
| Space detail / balances / expenses | Dense tabs and rows, scattered radii | Shared pressable, 8px section rhythm and radius scale |
| Add expense | Compact participant controls and inconsistent gaps | Accessible controls with consistent group spacing |
| Settle-up | Compact rows and irregular gaps | Shared motion and 8px spacing |
| Loans list / detail / confirmation | Direct repayment row taps and dense metadata | Shared feedback, 44px targets, grouped repayment content |
| New loan / repayment sheets | Compact chips and mixed radii | Shared tokens and scalable controls |
| Activity | Local motion constant and mixed row spacing | Shared motion and deliberate group spacing |
| Profile / export / edit / appearance | Dense rows and sheet spacing | Shared feedback, consistent sheet edges and row spacing |
| Sheets / dialogs / empty / error | Default panel timing and mixed compact controls | 200ms transitions, Reduce Motion, accessible actions |

Verification: extend the golden matrix to both 360x800 and 390x844, dark/light,
and 200% text; walk each rendered screen's semantic tap targets and reject any
under 44x44; retain existing behavior/semantics tests; root analyze; Linux golden
regeneration and exact-head pull_request CI including Android debug build.

Before evidence comes from the base commit's Linux golden PNGs. After evidence
must come from the Linux regeneration workflow, never macOS raster output.

## Owner update: Liquid Glass navigation

Use Flutter emulation on both platforms, without a new dependency. Apple's
[UIKit guidance](https://developer.apple.com/videos/play/wwdc2025/284/) describes
native glass bars; [native_liquid_glass](https://pub.dev/packages/native_liquid_glass)
provides UIKit platform views but documents whole-screen compositing cost, popup
overlay suppression, and manual handling for tab transitions. Flutter's
[UiKitView documentation](https://api.flutter.dev/flutter/widgets/UiKitView-class.html)
also calls out embedding cost. For this change, platform views cannot be justified
as a robust replacement for the tested shell and owner-approved bronze gradient;
this is a compatibility decision, not a claim that those packages are unmaintained.

The capsule uses a 28-sigma backdrop blur, a 1.15 saturation matrix, existing
surface tint, a fading 1px specular edge, a restrained inner glow, and layered
ambient shadows. Its bronze pill slides for 250ms with ease-out. High contrast
and explicit low-end mode use an opaque surface. Android falls back after twelve
raster frames above 20ms in a thirty-frame window; the decision stays stable for
the bar's lifetime. Reduce Motion disables both sliding and press scale.
Inactive icons/labels use existing primary text so contrast remains at least
4.5:1 even over extreme backgrounds; tests cover tint, glow, and bronze endpoints.
The shell retains content behind the bar. At text scale 1.3 and above, navigation
uses icons with semantic labels and long-press tooltips at the same capsule height.

## Accessibility refinements found during rendering

- Fixed double-scaled rupee WidgetSpans, with a rendered-size regression test.
- Fit complete money amounts to their available width; preserve spoken rupees.
- Keep normal action labels single-line with ellipsis; stack paired actions at
  large text sizes and fit whole labels without mid-word breaks.
- At 200% text, amount sheets use one scrolling form and schedule fields stack.
- The widget-tree target audit runs from every screen golden and each panel
  capture, with a negative test proving a 24px control fails. Flutter's native
  text-selection handles are excluded; app tap detectors are not.
- Before renders use the unchanged base source at the recorded SHA with the
  current screenshot fixtures at 100%; only the new target assertion is omitted
  for the base. Head runs all assertions and the full 100%/200% matrix.


## Reproducing the evidence

Linux workflow run 42838601608 generated the original before images. Run
42850893604 regenerated app/core goldens, 38 comparison sheets and content pixel
deltas for the review fixes and both owner changes. Its rendering and composition
steps passed; GitHub rejected the final ref update with `fatal error in commit_refs`.
The generated commit ff4bbba7ef6348fe40ad2ecb4887507083a45358 was fetched by SHA
and fast-forwarded locally, preserving the exact Linux artifacts. The temporary workflow additions were
removed after generation; this PR leaves `.github` identical to main. The scripts
remain usable in a Linux checkout with Flutter dependencies installed:

```sh
scripts/capture-ui-baseline.sh b60a54cc5872a4aa15ca93d5a7d395e9447e3e7b
(cd app && flutter test --update-goldens)
python3 scripts/compose-ui-evidence.py  # Pillow 11.3.0
```

The comparison sheets show both viewports and themes, with before/after at 100%
and the after view at 200%. Full-resolution source images remain beside the tests.

## PR 146 fix-round checkpoint (2026-11-10)

The checklist below supersedes conflicting first-round notes above. This is an
implementation checkpoint, not a claim of final verification or merge readiness.
No palette or font-family changes are intended; the owner explicitly approved
growth within the Welcome/Home composition to accommodate the new type ramp.

- [x] **Review fixes implemented:** 20px card / 24px hero padding, 24/32px
  section rhythm, micro-borders and layered ambient shadows, fewer dividers,
  42% glass tint with 28-sigma blur and local 72% legibility plates, icon-only
  navigation at larger text sizes, single-line action labels, responsive paired
  actions, and expanded sheet hit-target / mid-word-wrap audits.
- [x] **Global type ramp implemented:** named Figtree HIG roles from 34px large
  title through 12px caption, with 11px reserved for tab labels; feature-level
  raw font sizing replaced by roles, body/input text at 17px, hero amounts
  retained, and source/tree contract tests added.
- [x] **Native scrolling implemented:** shared sliver scaffold with pinned glass
  chrome and covered status region, platform refresh/physics, per-tab positions,
  active-tab scroll-to-top, iOS status tap and swipe-back, drag keyboard dismissal,
  panel drag/fling dismissal, haptics, native routes, and Reduce Motion handling.
- [x] **Local verification:** root analyze is clean; all 646 app tests, 370 core
  tests, all feature-package suites and 51 targeted Loans tests pass. Profile tests now
  reveal offscreen settings rows before tapping, preserving no-pump double-tap
  checks; receipt tests reveal lazy sliver content before asserting it.
- [ ] **Finish visual evidence:** review both sizes/themes at 100% and 200%,
  regenerate authoritative Linux goldens and comparison sheets, and add pixel
  deltas. All local macOS diagnostic PNG changes were deleted/restored before Linux
  regeneration; original before images remain the baseline.
- [ ] **Finish delivery:** restore any temporary workflow dispatch changes so
  `.github` has an empty base diff, verify pull_request CI on the exact final head
  including Android debug, run `flutter clean`, push and reply on PR 146 without
  merging, then report completion through Orca.
