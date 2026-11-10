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
| [0007](0007-supabase-flutter.md) | Supabase client: supabase_flutter | Proposed |
| [0008](0008-integration-test.md) | Integration tests: the SDK's integration_test | Proposed |
| [0009](0009-native-splash-and-icons.md) | Native splash and app icon: flutter_native_splash and flutter_launcher_icons | Proposed |
| [0010](0010-theme-preference.md) | Persist the device-local theme preference with shared_preferences | Accepted |
| [0011](0011-url-launcher.md) | Opening UPI apps and WhatsApp: url_launcher, and the Android chooser | Proposed |
| [0012](0012-offline-store.md) | Offline store: drift without codegen, opened by drift_flutter | Proposed |
| [0013](0013-live-activity-and-ongoing-notification.md) | Live Activity and the Android ongoing notification: plugin-less, driven by app state | Proposed |
| [0014](0014-statements-pdf-share.md) | Statements and exports: pdf on device, share_plus to share | Proposed |
| [0014](0014-ios-release-signing.md) | iOS release signing: cloud-managed, through the App Store Connect API key | Proposed |

Owner-level process calls that are not architecture live in `docs/decisions/`.
