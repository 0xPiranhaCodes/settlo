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
  testWidgets('loan nudges have polite Activity copy', (tester) async {
    await _pump(
      tester,
      FakeActivityRepository(
        entries: [
          for (final (id, action) in [
            (10, ActivityAction.reminded),
            (9, ActivityAction.due),
          ])
            ActivityEntry(
              id: id,
              at: DateTime(2026, 11, 9),
              kind: ActivityKind.loan,
              action: action,
              byYou: false,
              loanId: 'loan',
              counterparty: 'Friend',
            ),
        ],
      ),
    );
    expect(find.text('A gentle reminder to check your loan'), findsOneWidget);
    expect(find.text('An instalment was due yesterday'), findsOneWidget);
  });

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
    expect(
      find.text('₹1,099 → ₹1,199 · Flat 402 · 3 Nov · Question this'),
      findsOneWidget,
    );
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

    await tester.scrollUntilVisible(
      find.text('Priya added Chai 1'),
      400,
      scrollable: find.byType(Scrollable).first,
    );
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
    await tester.scrollUntilVisible(
      find.text('Priya added Chai 1'),
      400,
      scrollable: find.byType(Scrollable).first,
    );
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
    await tester.fling(
      find.byType(CustomScrollView),
      const Offset(0, 400),
      1000,
    );
    await tester.pumpAndSettle();

    expect(activity.calls.where((c) => c.startsWith('feed')), ['feed 30 null']);
    expect(activity.calls, contains('needsYou'));
    expect(find.text('Rahul added Late chai'), findsOneWidget);
  });

  group('filters (#109)', () {
    testWidgets('a space chip and Loans read the feed through the filter', (
      tester,
    ) async {
      final activity = FakeActivityRepository();
      await _pump(tester, activity);
      List<String> feeds() =>
          activity.calls.where((c) => c.startsWith('feed')).toList();

      await tester.tap(find.text('Flat 402'));
      await tester.pumpAndSettle();
      expect(feeds().last, 'feed 30 null s1');
      expect(find.text('Priya added Electricity'), findsOneWidget);
      expect(find.text('Kabir settled with you'), findsNothing);
      expect(find.text('Arjun repaid · you confirmed'), findsNothing);
      // What waits for you stays on top under any filter.
      expect(find.text('Arjun recorded a ₹25,000 repayment'), findsOneWidget);

      await tester.ensureVisible(find.text('Loans'));
      await tester.tap(find.text('Loans'));
      await tester.pumpAndSettle();
      expect(feeds().last, 'feed 30 null loans');
      expect(find.text('Arjun repaid · you confirmed'), findsOneWidget);
      expect(find.text('Priya added Electricity'), findsNothing);

      await tester.ensureVisible(find.text('All'));
      await tester.tap(find.text('All'));
      await tester.pumpAndSettle();
      expect(feeds().last, 'feed 30 null');
      expect(find.text('Priya added Electricity'), findsOneWidget);
      expect(find.text('Arjun repaid · you confirmed'), findsOneWidget);
    });

    testWidgets('a filtered feed pages by keyset through the same filter', (
      tester,
    ) async {
      final entries = [
        for (var id = 90; id > 0; id--)
          ActivityEntry(
            id: id,
            at: DateTime(2026, 11, 9, 9).subtract(Duration(minutes: 90 - id)),
            kind: ActivityKind.expense,
            action: ActivityAction.created,
            byYou: false,
            actor: 'Priya',
            // Every other row is in Flat 402.
            spaceId: id.isEven ? 's1' : 's2',
            spaceName: id.isEven ? 'Flat 402' : 'Goa trip',
            description: 'Chai $id',
            amount: Paise.rupees(id),
          ),
      ];
      final activity = FakeActivityRepository(entries: entries, pending: []);
      await _pump(tester, activity);
      await tester.tap(find.text('Flat 402'));
      await tester.pumpAndSettle();
      activity.calls.clear();

      await tester.scrollUntilVisible(
        find.text('Priya added Chai 2'),
        400,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.pumpAndSettle();

      // The cursor is the 30th Flat 402 row, not the 30th row.
      expect(activity.calls.where((c) => c.startsWith('feed')), [
        'feed 30 32 s1',
      ]);
      expect(find.text('Priya added Chai 3'), findsNothing);
    });

    testWidgets('a filter with nothing in it says so', (tester) async {
      await _pump(
        tester,
        FakeActivityRepository(entries: [activityFeed.first], pending: []),
      );

      await tester.ensureVisible(find.text('Loans'));
      await tester.tap(find.text('Loans'));
      await tester.pumpAndSettle();
      expect(find.text('Nothing here yet'), findsOneWidget);
      expect(
        find.text('Loans and repayments you are part of show up here.'),
        findsOneWidget,
      );

      await tester.ensureVisible(find.text('Goa trip'));
      await tester.tap(find.text('Goa trip'));
      await tester.pumpAndSettle();
      expect(
        find.text(
          'Expenses and settle-ups in this space show up here, '
          'edits included.',
        ),
        findsOneWidget,
      );
    });
  });

  group('bell (#109)', () {
    testWidgets('counts what is new since the last open, then marks it seen', (
      tester,
    ) async {
      // Last open on 3 Nov at 22:00: Kabir's settle-up and Priya's
      // electricity are new; your own two entries never count.
      final activity = FakeActivityRepository(
        seenAt: DateTime(2026, 11, 3, 22),
      );
      await _pump(tester, activity);

      expect(find.byTooltip('Notifications, 2 new'), findsOneWidget);
      expect(find.text('2'), findsOneWidget);
      expect(activity.calls, contains('markSeen'));
      expect(activity.seenAt, activityFeed.first.at);

      // Looking again: nothing is new any more.
      await tester.fling(
        find.byType(CustomScrollView),
        const Offset(0, 400),
        1000,
      );
      await tester.pumpAndSettle();
      expect(find.byTooltip('Notifications'), findsOneWidget);
      expect(find.text('2'), findsNothing);
    });

    testWidgets('a question about your edit rings for you, the editor, only', (
      tester,
    ) async {
      // Asked at 10:00 on 9 Nov, after every entry, about an edit made on
      // 3 Nov; you last looked at 09:45.
      List<ActivityEntry> feed({required bool yours}) => [
        for (final e in activityFeed)
          if (e.action == ActivityAction.edited)
            ActivityEntry(
              id: e.id,
              at: e.at,
              kind: e.kind,
              action: e.action,
              byYou: yours,
              actor: yours ? 'Sana' : e.actor,
              spaceId: e.spaceId,
              spaceName: e.spaceName,
              description: e.description,
              amount: e.amount,
              beforeAmount: e.beforeAmount,
              questions: [
                (
                  byYou: false,
                  name: 'Priya',
                  note: 'Why?',
                  at: DateTime(2026, 11, 9, 10),
                ),
              ],
            )
          else
            e,
      ];
      final seenAt = DateTime(2026, 11, 9, 9, 45);

      // Rahul's edit: Priya's question is for Rahul, not for you.
      await _pump(
        tester,
        FakeActivityRepository(entries: feed(yours: false), seenAt: seenAt),
      );
      expect(find.byTooltip('Notifications'), findsOneWidget);

      // Your edit: it is for you, and opening Activity marks it seen.
      final activity = FakeActivityRepository(
        entries: feed(yours: true),
        seenAt: seenAt,
      );
      await _pump(tester, activity);
      expect(find.byTooltip('Notifications, 1 new'), findsOneWidget);
      expect(find.text('Priya asked: “Why?”'), findsOneWidget);
      expect(activity.seenAt, DateTime(2026, 11, 9, 10));
    });

    testWidgets('with nothing new it is plain and marks nothing', (
      tester,
    ) async {
      final activity = FakeActivityRepository();
      await _pump(tester, activity);

      expect(find.byTooltip('Notifications'), findsOneWidget);
      expect(activity.calls, isNot(contains('markSeen')));
    });

    testWidgets('goes back to everything, from the newest', (tester) async {
      final activity = FakeActivityRepository();
      await _pump(tester, activity);
      await tester.ensureVisible(find.text('Loans'));
      await tester.tap(find.text('Loans'));
      await tester.pumpAndSettle();
      expect(find.text('Priya added Electricity'), findsNothing);

      await tester.tap(find.byTooltip('Notifications'));
      await tester.pumpAndSettle();
      expect(find.text('Priya added Electricity'), findsOneWidget);
      expect(tester.widget<SChip>(find.byType(SChip).first).selected, isTrue);
    });
  });

  group("'Question this' (#109)", () {
    testWidgets("someone else's edit takes a short note, shown on its row", (
      tester,
    ) async {
      final activity = FakeActivityRepository();
      await _pump(tester, activity);

      await tester.ensureVisible(find.text('Rahul edited Wifi · Airtel'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Rahul edited Wifi · Airtel'));
      await tester.pumpAndSettle();
      expect(find.text('Question this edit'), findsOneWidget);
      expect(
        find.text(
          'Ask Rahul about the change to Wifi · Airtel. Everyone in '
          'Flat 402 sees your note here in Activity.',
        ),
        findsOneWidget,
      );
      // Nothing to send yet.
      expect(
        tester.widget<SPrimaryButton>(find.byType(SPrimaryButton)).onPressed,
        isNull,
      );
      expect(
        tester.widget<TextField>(find.byType(TextField)).maxLength,
        questionMaxLength,
      );

      await tester.enterText(
        find.byType(TextField),
        'Why ₹100 more? Call 98000 00009',
      );
      await tester.pump();
      await tester.tap(find.text('Send'));
      await tester.pumpAndSettle();

      expect(
        activity.calls,
        contains('question 2 Why ₹100 more? Call 98000 00009'),
      );
      expect(find.text('Question this edit'), findsNothing);
      // The number never shows, and one question is all you get.
      expect(
        find.text('You asked: “Why ₹100 more? Call ••••”'),
        findsOneWidget,
      );
      expect(find.text('₹1,099 → ₹1,199 · Flat 402 · 3 Nov'), findsOneWidget);
    });

    testWidgets('a note that cannot be sent stays to try again', (
      tester,
    ) async {
      final activity = FakeActivityRepository()..questionFails = true;
      await _pump(tester, activity);

      await tester.ensureVisible(find.text('Rahul edited Wifi · Airtel'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Rahul edited Wifi · Airtel'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), 'Why?');
      await tester.pump();
      await tester.tap(find.text('Send'));
      await tester.pumpAndSettle();

      expect(find.text("We couldn't send that. Try again."), findsOneWidget);
      expect(find.text('Send'), findsOneWidget);
      // Typing again clears the error.
      await tester.enterText(find.byType(TextField), 'Why now?');
      await tester.pump();
      expect(find.text("We couldn't send that. Try again."), findsNothing);
    });

    testWidgets("members' notes show; your own edit cannot be questioned", (
      tester,
    ) async {
      ActivityEntry edit(int id, {required bool byYou}) => ActivityEntry(
        id: id,
        at: DateTime(2026, 11, 9, 9, id),
        kind: ActivityKind.expense,
        action: ActivityAction.edited,
        byYou: byYou,
        actor: byYou ? 'Sana' : 'Rahul',
        spaceId: 's1',
        spaceName: 'Flat 402',
        description: 'Rent $id',
        amount: const Paise.rupees(1200),
        beforeAmount: const Paise.rupees(1100),
        questions: const [
          (byYou: false, name: 'Priya', note: 'Was this agreed?', at: null),
          (byYou: false, name: null, note: 'Same question', at: null),
        ],
      );
      await _pump(
        tester,
        FakeActivityRepository(
          entries: [edit(2, byYou: false), edit(1, byYou: true)],
          pending: [],
        ),
      );

      expect(find.text('Priya asked: “Was this agreed?”'), findsNWidgets(2));
      expect(find.text('Someone asked: “Same question”'), findsNWidgets(2));
      expect(
        find.text('₹1,100 → ₹1,200 · Flat 402 · 9 Nov · Question this'),
        findsOneWidget,
      );
      await tester.tap(find.text('You edited Rent 1'));
      await tester.pumpAndSettle();
      expect(find.text('Question this edit'), findsNothing);
    });
  });
}
