import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:settlo_activity/settlo_activity.dart';
import 'package:settlo_core/settlo_core.dart';
import 'package:settlo_loans/settlo_loans.dart';
import 'package:settlo_spaces/settlo_spaces.dart';
import 'package:settlo_test_support/golden.dart';

import 'support/fake_activity.dart';
import 'support/fake_session.dart';
import 'support/fake_space_ledger.dart';
import 'support/fake_spaces.dart';

/// The Activity tab with the routes it opens, at 360x800 on 9 Nov.
Future<GoRouter> _pump(
  WidgetTester tester,
  FakeActivityRepository activity, {
  FakeSpaceLedgerRepository? ledger,
}) async {
  await loadSettloFonts();
  tester.view
    ..physicalSize = SettloGoldenDevices.compact360.size
    ..devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final router = GoRouter(
    initialLocation: SettloRoutes.activity,
    routes: [...spacesRoutes, ...loansRoutes, activityTabRoute],
  );
  addTearDown(router.dispose);
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        sessionProvider.overrideWith(() => FakeSessionNotifier(fakeSession)),
        activityRepositoryProvider.overrideWithValue(activity),
        activityNowProvider.overrideWithValue(DateTime(2026, 11, 9, 18)),
        spacesRepositoryProvider.overrideWithValue(
          FakeSpacesRepository(spacesList),
        ),
        spaceLedgerRepositoryProvider.overrideWithValue(
          ledger ?? FakeSpaceLedgerRepository(),
        ),
      ],
      child: MaterialApp.router(
        theme: SettloTheme.dark(),
        routerConfig: router,
      ),
    ),
  );
  await tester.pumpAndSettle();
  return router;
}

/// Activity with Rahul's settle-up waiting in Flat 402's ledger.
({FakeActivityRepository activity, FakeSpaceLedgerRepository ledger})
_withSettleUp() {
  final ledger = FakeSpaceLedgerRepository({
    's1': flatLedgerWithSettleUp,
    's2': tripLedger,
  });
  return (
    activity: FakeActivityRepository(
      pending: [rahulSettleUpAnswer, arjunRepaymentAnswer],
      ledger: ledger,
    ),
    ledger: ledger,
  );
}

/// Rahul's settle-up is listed first, before Arjun's repayment.
Finder get _reviewRahul => find.text('Review').first;

void main() {
  testWidgets('the feed reads like the canvas, edits before and after', (
    tester,
  ) async {
    await _pump(tester, FakeActivityRepository());

    expect(find.text('Arjun recorded a ₹25,000 repayment'), findsOneWidget);
    expect(find.text('needs your confirmation · 5 Oct'), findsOneWidget);
    expect(find.text('Today'), findsOneWidget);
    expect(find.text('This week'), findsOneWidget);
    expect(find.text('Priya added Electricity'), findsOneWidget);
    expect(find.text('You added Groceries'), findsOneWidget);
    expect(find.text('Arjun repaid · you confirmed'), findsOneWidget);
    expect(find.text('Kabir settled with you'), findsOneWidget);
    expect(find.text('Rahul edited Wifi · Airtel'), findsOneWidget);
    expect(find.text('₹1,099 → ₹1,199 · Flat 402 · 3 Nov'), findsOneWidget);
    // The change is read in rupees, never as glyphs.
    expect(
      find.bySemanticsLabel(
        RegExp(
          'one thousand ninety-nine rupees to one thousand one hundred '
          'ninety-nine rupees',
        ),
      ),
      findsOneWidget,
    );
  });

  testWidgets('only money in or out of your pocket is coloured', (
    tester,
  ) async {
    await _pump(tester, FakeActivityRepository());

    MoneyTone toneOf(int rupees) => tester
        .widget<MoneyText>(
          find.byWidgetPredicate(
            (w) => w is MoneyText && w.amount == Paise.rupees(rupees),
          ),
        )
        .tone;
    expect(toneOf(25000), MoneyTone.owedToYou);
    expect(toneOf(1200), MoneyTone.owedToYou);
    expect(toneOf(2340), MoneyTone.neutral);
    expect(toneOf(1800), MoneyTone.neutral);
    expect(toneOf(1199), MoneyTone.neutral);
  });

  testWidgets("'Needs you' narrows to what waits for you", (tester) async {
    final (:activity, :ledger) = _withSettleUp();
    await _pump(tester, activity, ledger: ledger);

    await tester.tap(find.text('Needs you · 2'));
    await tester.pumpAndSettle();
    expect(find.text('Rahul recorded a ₹300 settle-up'), findsOneWidget);
    expect(find.text('Arjun recorded a ₹25,000 repayment'), findsOneWidget);
    expect(
      find.text('Flat 402 · needs your confirmation · 9 Nov'),
      findsOneWidget,
    );
    expect(find.text('Priya added Electricity'), findsNothing);
    expect(find.text('Today'), findsNothing);

    await tester.tap(find.text('All'));
    await tester.pumpAndSettle();
    expect(find.text('Priya added Electricity'), findsOneWidget);
  });

  testWidgets('empty: says what will show up, in both filters', (tester) async {
    await _pump(tester, FakeActivityRepository(entries: [], pending: []));

    expect(find.text('No activity yet'), findsOneWidget);
    expect(find.text('Review'), findsNothing);

    await tester.tap(find.text('Needs you'));
    await tester.pumpAndSettle();
    expect(find.text('Nothing needs you'), findsOneWidget);
    expect(find.text('No activity yet'), findsNothing);
  });

  testWidgets('confirming a settle-up from the feed uses the space sheet, then '
      'refreshes', (tester) async {
    final (:activity, :ledger) = _withSettleUp();
    final router = await _pump(tester, activity, ledger: ledger);

    await tester.tap(_reviewRahul);
    await tester.pumpAndSettle();
    expect(
      router.state.uri.toString(),
      SettloRoutes.confirmSettlement('s1', 'e11'),
    );
    expect(find.text('Confirm settle-up · Flat 402'), findsOneWidget);
    expect(find.text('RAHUL SAYS THEY PAID YOU'), findsOneWidget);

    final reads = activity.calls.where((c) => c == 'needsYou').length;
    await tester.tap(find.text('Yes, I received ₹300'));
    await tester.pumpAndSettle();

    expect(ledger.calls.single, startsWith('confirm '));
    expect(ledger.calls.single, endsWith(' e11 30000 m2'));
    expect(router.state.uri.toString(), SettloRoutes.activity);
    expect(
      activity.calls.where((c) => c == 'needsYou').length,
      greaterThan(reads),
    );
    expect(find.text('Rahul recorded a ₹300 settle-up'), findsNothing);
    expect(find.text('Needs you · 1'), findsOneWidget);
  });

  testWidgets('Review on a repayment opens its confirmation', (tester) async {
    final router = await _pump(tester, FakeActivityRepository());

    await tester.tap(find.text('Review'));
    await tester.pumpAndSettle();
    expect(router.state.uri.toString(), SettloRoutes.confirmRepayment('r3'));
  });

  testWidgets('link-only decline says the underlying invite remains open', (
    tester,
  ) async {
    await _pump(
      tester,
      FakeActivityRepository(
        entries: [
          ActivityEntry(
            id: 99,
            at: DateTime(2026, 11, 10),
            kind: ActivityKind.member,
            action: ActivityAction.rejected,
            byYou: false,
            description: 'Kabir',
            linkOnly: true,
          ),
        ],
        pending: const [],
      ),
    );

    expect(
      find.text(
        "Someone with your link said it isn't them. The invite to Kabir "
        'is still open.',
      ),
      findsOneWidget,
    );
  });

  testWidgets('a double tap on Review in one frame opens it once', (
    tester,
  ) async {
    final (:activity, :ledger) = _withSettleUp();
    await _pump(tester, activity, ledger: ledger);

    final review = _reviewRahul;
    await tester.tap(review);
    await tester.tap(review, warnIfMissed: false);
    await tester.pumpAndSettle();

    expect(find.byType(ConfirmSettlementScreen), findsOneWidget);
  });

  testWidgets('a settle-up already answered says so', (tester) async {
    final ledger = FakeSpaceLedgerRepository();
    final router = await _pump(
      tester,
      FakeActivityRepository(pending: [rahulSettleUpAnswer]),
      ledger: ledger,
    );

    await tester.tap(find.text('Review'));
    await tester.pumpAndSettle();
    expect(find.textContaining('already answered'), findsOneWidget);

    await tester.tap(find.bySemanticsLabel('Close'));
    await tester.pumpAndSettle();
    expect(router.state.uri.toString(), SettloRoutes.activity);
  });

  testWidgets('scrolling to the end loads the next page by keyset', (
    tester,
  ) async {
    final entries = [
      for (var id = 40; id > 0; id--)
        ActivityEntry(
          id: id,
          at: DateTime(2026, 11, 9, 8),
          kind: ActivityKind.expense,
          action: ActivityAction.created,
          byYou: false,
          actor: 'Priya',
          spaceName: 'Flat 402',
          description: 'Chai $id',
          amount: Paise.rupees(id),
        ),
    ];
    final activity = FakeActivityRepository(entries: entries, pending: []);
    await _pump(tester, activity);
    expect(activity.calls.where((c) => c.startsWith('feed')), ['feed 30 null']);

    await tester.scrollUntilVisible(find.text('Priya added Chai 1'), 400);
    await tester.pumpAndSettle();

    expect(activity.calls.where((c) => c.startsWith('feed')), [
      'feed 30 null',
      'feed 30 11',
    ]);
    expect(find.text('Priya added Chai 1'), findsOneWidget);
  });

  testWidgets('pull to refresh drops the cursor and reloads from the top', (
    tester,
  ) async {
    final entries = [
      for (var id = 40; id > 0; id--)
        ActivityEntry(
          id: id,
          at: DateTime(2026, 11, 9, 8),
          kind: ActivityKind.expense,
          action: ActivityAction.created,
          byYou: false,
          actor: 'Priya',
          spaceName: 'Flat 402',
          description: 'Chai $id',
          amount: Paise.rupees(id),
        ),
    ];
    final activity = FakeActivityRepository(entries: entries, pending: []);
    await _pump(tester, activity);
    await tester.scrollUntilVisible(find.text('Priya added Chai 1'), 400);
    await tester.pumpAndSettle();
    // A late commit (docs/api.md) lands among rows already paged past.
    entries.insert(
      0,
      ActivityEntry(
        id: 41,
        at: DateTime(2026, 11, 9, 9),
        kind: ActivityKind.expense,
        action: ActivityAction.created,
        byYou: false,
        actor: 'Rahul',
        spaceName: 'Flat 402',
        description: 'Late chai',
        amount: const Paise.rupees(41),
      ),
    );
    activity.calls.clear();

    tester
        .state<ScrollableState>(find.byType(Scrollable).first)
        .position
        .jumpTo(0);
    await tester.pump();
    await tester.fling(find.byType(ListView), const Offset(0, 400), 1000);
    await tester.pumpAndSettle();

    expect(activity.calls.where((c) => c.startsWith('feed')), ['feed 30 null']);
    expect(activity.calls, contains('needsYou'));
    expect(find.text('Rahul added Late chai'), findsOneWidget);
  });
}
