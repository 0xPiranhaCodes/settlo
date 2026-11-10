# Issue 145 design audit and test plan

The shared screen edge is 20 logical pixels. The coordinator approved a single
mock-fidelity exception: Welcome retains its 24px inset and warm action shadow.
Colours, Figtree typography, routes, keys, providers and mutation guards stay intact.

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
The shell retains content behind the bar and increases its bottom inset when
large navigation labels need a taller capsule.

## Accessibility refinements found during rendering

- Fixed double-scaled rupee WidgetSpans, with a rendered-size regression test.
- Fit complete money amounts to their available width; preserve spoken rupees.
- Allow primary action labels to wrap instead of truncating confirmation amounts.
- At 200% text, amount sheets use one scrolling form and schedule fields stack.
- The widget-tree target audit runs from every screen golden and each panel
  capture, with a negative test proving a 24px control fails. Flutter's native
  text-selection handles are excluded; app tap detectors are not.
- Before renders use the unchanged base source at the recorded SHA with the
  current screenshot fixtures at 100%; only the new target assertion is omitted
  for the base. Head runs all assertions and the full 100%/200% matrix.


## Reproducing the evidence

Linux workflow run 42838601608 generated the before images, updated app/core
goldens, and per-screen comparison sheets. The temporary workflow additions were
removed after generation; this PR leaves `.github` identical to main. The scripts
remain usable in a Linux checkout with Flutter dependencies installed:

```sh
scripts/capture-ui-baseline.sh b60a54cc5872a4aa15ca93d5a7d395e9447e3e7b
(cd app && flutter test --update-goldens)
python3 scripts/compose-ui-evidence.py  # Pillow 11.3.0
```

The comparison sheets show both viewports and themes, with before/after at 100%
and the after view at 200%. Full-resolution source images remain beside the tests.
