# Issue 170: in-app S mark follows the theme

Before and after images are the 390x844 goldens: `before-*` are from `main`,
and `after-*` were regenerated on ubuntu-24.04 by the hosted CI golden job
(commit `test: regenerate goldens on ubuntu-24.04`).

| Screen | Light | Dark |
| --- | --- | --- |
| Home (`home_main`) | muted gold mark → ink | gold mark → white |
| Welcome (`auth_welcome`) | always dark: gold mark → white | gold mark → white |
| Join (`join`) | ink, unchanged | gold mark → white |
| Sign-in (`auth_phone`) | no mark, unchanged | no mark, unchanged |

The sign-in steps (phone and OTP) render no S mark, so their goldens did not
change; the images are included to show that. The app icon and launch screen
are out of scope and unchanged.
