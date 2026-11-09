# Architecture decision records

One file per decision: Context, Decision, Consequences, Status. Superseding an ADR means a new ADR that links the old one; the old one's status becomes `Superseded by NNNN`.

| ADR | Title | Status |
| --- | --- | --- |
| [0001](0001-stack.md) | Stack and decisions already taken | Accepted |
| [0002](0002-package-boundaries.md) | Package boundaries and dependency direction | Accepted |
| [0003](0003-money.md) | Money as integer paise; split and simplification rules | Accepted |
| [0004](0004-offline-sync.md) | Offline: drift mirror and `pending_mutations` queue | Accepted |
| [0005](0005-dependency-policy.md) | Dependency policy | Accepted |
| [0006](0006-fonts.md) | Fonts: bundled Figtree and IBM Plex Serif, no google_fonts | Accepted |

Owner-level process calls that are not architecture live in `docs/decisions/`.
