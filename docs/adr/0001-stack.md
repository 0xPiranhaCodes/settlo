# 0001 Stack and decisions already taken

## Status
Accepted (9 Nov 2026)

## Context
Settlo is a shared-finance record for India: spaces with fair-share balances, and person-to-person loans with two-sided confirmation. The owner fixed the product and platform choices before work started; they are listed in [the context pack](../context-pack.md) under "Decisions already taken". Agents need one place that states them so they are not re-argued in PRs. PR #17 also had to pick a monorepo tool.

## Decision
These are settled and are not reopened by any agent:

- Flutter (stable, Dart 3) over React Native; iOS and Android only.
- Supabase (Postgres, phone OTP auth, RLS, RPCs, Edge Functions) over Firebase.
- Phone number (E.164) is the only identity. No email, no password.
- Dark-first UI; Figtree for text, IBM Plex Serif for amounts at 20px and above.
- Gold accent means a tappable primary action only.
- Loan repayments need two-sided confirmation (recorded by one party, confirmed by the other).
- Settlo never holds or moves money; settling is a UPI deep link.
- INR only in v1.
- Loans are interest-free in v1 (schema reserves interest types).

App stack, from the context pack: Riverpod with codegen, go_router, freezed + json_serializable, drift, google_fonts, firebase_messaging, url_launcher, share_plus, flutter_contacts, live_activities, home_widget, flutter_native_splash, very_good_analysis lints.

Monorepo: a Dart pub workspace (root `pubspec.yaml` with `workspace:`, each member `resolution: workspace`), not Melos. Codegen runs through `scripts/codegen.sh` (`dart run build_runner build --workspace`).

## Consequences
- One root `pubspec.lock` and one resolution for all 12 members; `flutter analyze` runs once from the root.
- No Melos dependency. Its script aliases are replaced by small scripts in `scripts/`; per-member test runs are CI's job (`flutter test <member>` for each member with a `test/` directory), since root `flutter test` finds nothing.
- The listed packages are approved in principle but are still added only by the issue that first imports them ([0005](0005-dependency-policy.md)).
- Changing anything in the "settled" list needs the owner, not an ADR.
