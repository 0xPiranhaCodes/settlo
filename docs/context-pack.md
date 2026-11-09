# Settlo — Context pack (v1, 9 Nov 2026)

Shared memory for every agent. Canvas snapshot: `design/canvas/` (artboard sources `*.dc.html`; rationale notes in `canvas.json` → `notes`). Role prompts: `docs/roles.md`.

## Product
Settlo is a shared-finance tracker for India. It is a record, not a lender and not a wallet: it never holds or moves money. Two jobs:
1. Spaces — flatmates, trips, or one friend share expenses. Beyond who-owes-whom, the product shows fairness: what each person paid against their fair share, so a household can see that everyone is paying for everything. Debts are simplified to the minimum number of payments.
2. Loans — one person lends another a large sum (e.g. ₹10 lakh) repaid monthly. Both parties see the loan; every repayment is recorded by one side and confirmed by the other. Interest-free in v1; schema reserves simple and reducing-balance interest for later (needs a legal read first).

Identity is the phone number. No email, no password. Spaces and loans can be created against numbers that have not joined; when that number verifies, everything recorded against it appears for review. Nothing about a number is revealed before it is verified.

Audience: Indian users, INR only in v1, UPI for settling (deep link `upi://pay` with amount and payee VPA prefilled, plus app chooser). WhatsApp is the primary share and reminder channel with SMS and in-app fallbacks.

## Brand and design
- Name: Settlo. Mark: an S built from two interlocking halves (asset provided by owner). Wordmark: lowercase `settlo` in Figtree Medium, tight tracking.
- Dark-first. Background #0A0B0D; surfaces #15171A, #1E2126, #262A30; hairlines rgba(255,255,255,0.07); every card has a 1px top specular rgba(255,255,255,0.10). No gradients, no illustrations, no emoji.
- Text: primary #F3F2EE, secondary #9B9D9A, muted #8A8D88.
- Accent gold #D8B36A on #0A0B0D text. Gold means exactly one thing: a tappable primary action (and the focused OTP box). Never for progress, ticks, badges or status.
- Money colours: owed to you = mint #5BD39B, you owe = coral #F0715C, settled = secondary grey. No other use of green or red anywhere.
- Light theme: paper #F4F1EA, ink #1B1B18 replaces gold as primary action, mint #1E7F5C, coral #B6342B.
- Type: Figtree (variable 400–700) for all text; body 400, labels and buttons 500. IBM Plex Serif 500 for every amount at 20px and above, tabular figures. Amounts in lists use Figtree tabular. The ₹ sign is always Figtree at ~56% of the number, aligned to cap height.
- Shape: cards radius 24–28, buttons 16, chips pill, 8pt grid, 20px screen margins, 44pt minimum touch targets.
- Glass only for chrome: floating tab bar (68px pill, blur 28, 62% surface, 1px specular border). Android mid-range falls back to a flat 92% surface. Never blur behind content or amounts.
- Sheets for amount entry (add expense, new loan, settle up); amount first, in the serif.
- Voice: plain, warm, no guilt. "Rahul owes you ₹420", never "in debt". Sentence case. No exclamation marks.
- Canvas is the source of truth: 22 artboards with a rationale note under each. Names: Splash, Welcome, Phone, Onboarding (OTP), Main (Home), HomeEmpty, HomeFound, SpacesList, SpaceExpenses, Space (balances), SpaceEmpty, AddExpense, Loan, NewLoan, Settle (request side), SettlePay (you pay), ConfirmRepayment, Activity, Profile, Join (invitee), LiveActivity, HomeLight.

## Architecture
- Flutter (stable), Dart 3, feature-first packages: core (theme, router, money, supabase client), features/auth, spaces, expenses, balances, loans, settle, activity, profile; local (drift db, sync queue); platform (live activities, widgets, deep links).
- State: Riverpod with codegen. Navigation: go_router. Models: freezed + json_serializable. Local: drift (SQLite) mirror plus `pending_mutations` queue replayed on reconnect with idempotency keys. Fonts via google_fonts. Push via firebase_messaging. UPI via url_launcher. Share via share_plus. Contacts via flutter_contacts with hashed lookups through an RPC; raw contacts never leave the device.
- Money: integer minor units (paise) everywhere, bigint in Postgres, int in Dart. Equal split: remainder paise go to the payer (payer first in the member order). Debt simplification: net each member, greedy match largest debtor to largest creditor; at most n-1 payments; runs on device.
- Backend: Supabase. Postgres schema: profiles(id, phone unique E.164, name, upi_id), friends, spaces, space_members(space_id, phone, user_id nullable, role), expenses(amount_minor, is_settlement, deleted_at), expense_payers, expense_splits(split_type equal|exact|percent|shares), recurring_expenses, loans(lender_phone, borrower_phone, *_id nullable, principal_minor, interest_type, schedule_type, installment_minor, due_day, closed_at), loan_repayments(amount_minor, principal_minor, interest_minor, recorded_by, confirmed_by, confirmed_at), activity. Deferred constraint trigger: sum(payers) = sum(splits) = amount. Triggers link phone to profile on sign-up. Views: space_member_balances, space_monthly_fairness, space_monthly_categories, loan_summaries. RLS: is_space_member(space_id) and is_loan_party(loan_id) keyed by phone or user id; activity read-only, written by triggers. RPCs: create_space(name, kind, members), add_expense(jsonb), lookup_phones(text[]) hashed, update_expense, delete_expense, add_space_members, leave_space, update_profile (#59).
- Auth: Supabase phone OTP. Dev: test phone numbers with fixed codes. Prod: Send-SMS auth hook to MSG91 (DLT registration is the owner's task). WhatsApp OTP as a later channel.
- iOS: Live Activity and Dynamic Island via a Swift widget extension bridged with the `live_activities` package, pushed through APNs from an Edge Function. Android: ongoing notification plus `home_widget` glance card. Splash via `flutter_native_splash` on #0A0B0D.
- Bundle ids `app.settlo` (iOS) and `app.settlo` (Android applicationId). Min iOS 16.1 (Live Activities), min Android 8.
- Quality: 80% unit coverage on money and sync; golden tests per screen at 390x844 and 360x800; pgTAP tests per RLS policy including negative cases; integration test for the flatmate flow (create space, add 3 expenses, settle) and the loan flow (create, repay, confirm).

## Decisions already taken (do not reopen)
Flutter over React Native; Supabase over Firebase; phone-only identity; dark-first; Figtree + IBM Plex Serif; gold accent for actions only; two-sided confirmation on repayments; Settlo never moves money; INR only in v1; interest-free loans in v1.

## Working rules for every agent
- Work only on your assigned issue, inside your own worktree, on branch `<issue>-<slug>`.
- Open a PR with `Closes #<issue>`, what changed, and evidence (screenshots at 390 and 360 for UI, test output for backend). Never merge your own PR.
- Money is integer paise. No new dependency without an ADR. Stay inside the paths your role owns (`docs/ownership.md` once it exists).
