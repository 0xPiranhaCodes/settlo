# Issue 145 design audit and test plan

The shared screen edge is 20 logical pixels. The coordinator approved a single
mock-fidelity exception: Welcome retains its 24px inset and warm action shadow.
Colours, Figtree typography, routes, keys, providers and mutation guards stay intact.

| Area | Findings | Planned refinement |
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
