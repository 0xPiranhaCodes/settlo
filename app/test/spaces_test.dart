import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:settlo/main.dart';
import 'package:settlo/shell.dart';
import 'package:settlo_balances/settlo_balances.dart';
import 'package:settlo_core/settlo_core.dart';
import 'package:settlo_spaces/settlo_spaces.dart';
import 'package:settlo_test_support/golden.dart';

import 'support/fake_home.dart';
import 'support/fake_session.dart';
import 'support/fake_space_ledger.dart';
import 'support/fake_spaces.dart';

/// Pumps the Spaces tab in the shell at [initialLocation] with
/// [repository], inside a router whose other routes record where the
/// screen sent the user.
Future<GoRouter> _pump(
  WidgetTester tester,
  FakeSpacesRepository repository, {
  String initialLocation = SettloRoutes.spaces,
  GoldenDevice device = SettloGoldenDevices.canvas390,
  FakeSpaceLedgerRepository? ledger,
}) async {
  await loadSettloFonts();
  tester.view
    ..physicalSize = device.size
    ..devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final router = GoRouter(
    initialLocation: initialLocation,
    routes: [
      GoRoute(
        path: SettloRoutes.spaces,
        builder: (_, _) => SettloShell(
          currentIndex: 1,
          onTabSelected: (_) {},
          child: const SpacesListScreen(),
        ),
        routes: [
          GoRoute(
            path: ':spaceId',
            builder: (_, state) => SettloShell(
              currentIndex: 1,
              onTabSelected: (_) {},
              child: SpaceExpensesScreen(
                spaceId: state.pathParameters['spaceId']!,
              ),
            ),
            routes: [
              GoRoute(
                path: 'balances',
                builder: (_, state) => SettloShell(
                  currentIndex: 1,
                  onTabSelected: (_) {},
                  child: SpaceScreen(spaceId: state.pathParameters['spaceId']!),
                ),
              ),
            ],
          ),
        ],
      ),
      for (final path in [
        SettloRoutes.addExpense,
        SettloRoutes.profile,
        SettloRoutes.settle,
        SettloRoutes.settlePay,
        SettloRoutes.activity,
      ])
        GoRoute(path: path, builder: (_, state) => Text('at ${state.uri}')),
    ],
  );
  addTearDown(router.dispose);
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        sessionProvider.overrideWith(() => FakeSessionNotifier(fakeSession)),
        spacesRepositoryProvider.overrideWithValue(repository),
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

Future<void> _openSheet(WidgetTester tester) async {
  await tester.tap(find.byTooltip('New space'));
  await tester.pumpAndSettle();
}

Future<void> _addPerson(WidgetTester tester, String phone, String name) async {
  await tester.enterText(find.widgetWithText(TextField, 'Phone number'), phone);
  await tester.enterText(find.widgetWithText(TextField, 'Their name'), name);
  await tester.ensureVisible(find.text('Add person'));
  await tester.tap(find.text('Add person'));
  await tester.pumpAndSettle();
}

Future<void> _tapCreate(WidgetTester tester) async {
  await tester.ensureVisible(find.text('Create space'));
  await tester.pumpAndSettle();
  await tester.tap(find.text('Create space'));
  await tester.pumpAndSettle();
}

/// Scrolls the screen's list to its end, so every row has been laid out.
Future<void> _scrollToEnd(WidgetTester tester) async {
  await tester.drag(find.byType(ListView), const Offset(0, -2000));
  await tester.pumpAndSettle();
}

void main() {
  test('spacesProvider creates a space and reloads it into the list', () async {
    final repository = FakeSpacesRepository(spacesList);
    final c = ProviderContainer(
      overrides: [spacesRepositoryProvider.overrideWithValue(repository)],
    );
    addTearDown(c.dispose);
    await c.read(spacesProvider.future);

    final id = await c
        .read(spacesProvider.notifier)
        .create(
          name: 'Flat 7C',
          kind: SpaceKind.flat,
          members: const [],
          idempotencyKey: 'k1',
        );

    expect(id, 's-new-0');
    expect(c.read(spacesProvider).requireValue.last.name, 'Flat 7C');
  });

  group('Spaces', () {
    testWidgets('each card is a mini balance sheet', (tester) async {
      await _pump(tester, FakeSpacesRepository(spacesList));

      expect(find.text('Rahul, Priya'), findsOne);
      expect(find.text('+₹2,850'), findsOne);
      expect(find.text('owed to you'), findsOne);
      expect(find.text('You paid 49% of ₹18,450'), findsOne);
      expect(find.text('fair share 33%'), findsOne);
      expect(find.text('5 people'), findsOne);
      expect(find.text('−₹3,650'), findsOne);
      expect(find.text('settled'), findsOne);
      // Only Flat 402 has spending this month.
      expect(find.textContaining('You paid'), findsOne);
      expect(find.text("Kabir hasn't joined yet"), findsOne);
      expect(
        find.text(
          '₹1,200 in Goa trip is recorded against +91\u00A0•••\u00A02210',
        ),
        findsOne,
      );
    });

    testWidgets('a payer who left still counts in the bar and history', (
      tester,
    ) async {
      final router = await _pump(
        tester,
        FakeSpacesRepository([spaceDepartedPayer]),
      );

      // You paid nothing; fair share 66,667 of 1,00,000 paise rounds to 67.
      expect(find.text('You paid 0% of ₹1,000'), findsOne);
      expect(find.text('fair share 67%'), findsOne);
      // Arun's segment, sized by the paise he paid.
      expect(
        find.byWidgetPredicate((w) => w is Expanded && w.flex == 100000),
        findsOne,
      );
      expect(find.text('−₹666.67'), findsOne);

      await tester.tap(find.text('Old flat'));
      await tester.pumpAndSettle();
      expect(router.state.uri.toString(), SettloRoutes.space('s7'));
      expect(find.text('NOVEMBER'), findsNothing, reason: 'not Space · empty');
      expect(find.byType(SpaceDetailView), findsOne);
    });

    testWidgets('the chips filter by kind', (tester) async {
      await _pump(tester, FakeSpacesRepository(spacesList));

      await tester.tap(find.text('Trips'));
      await tester.pumpAndSettle();
      expect(find.text('Goa trip'), findsOne);
      expect(find.text('Flat 402'), findsNothing);

      await tester.tap(find.text('Home').first);
      await tester.pumpAndSettle();
      expect(find.text('Flat 402'), findsOne);
      expect(find.text("Kabir hasn't joined yet"), findsNothing);

      await tester.tap(find.text('All'));
      await tester.pumpAndSettle();
      expect(find.text('Meera'), findsOne);
    });

    testWidgets('a card opens its space', (tester) async {
      final router = await _pump(tester, FakeSpacesRepository(spacesList));
      await tester.tap(find.text('Goa trip'));
      await tester.pumpAndSettle();
      expect(router.state.uri.toString(), SettloRoutes.space('s2'));
    });

    testWidgets('with no spaces it offers to start one', (tester) async {
      await _pump(tester, FakeSpacesRepository(const []));
      await tester.tap(find.text('Start a space'));
      await tester.pumpAndSettle();
      expect(find.text('New space'), findsOne);
    });

    testWidgets('a failed load says why, and pulling down reloads', (
      tester,
    ) async {
      final repository = FakeSpacesRepository(spacesList)
        ..failure = Exception('offline');
      await _pump(tester, repository);
      expect(find.textContaining("We couldn't load your spaces"), findsOne);

      await tester.fling(find.byType(ListView), const Offset(0, 400), 1000);
      await tester.pumpAndSettle();
      expect(find.text('Flat 402'), findsOne);
    });
  });

  group('New space', () {
    testWidgets('create space → it appears in the list', (tester) async {
      final repository = FakeSpacesRepository(spacesList);
      await _pump(tester, repository);
      await _openSheet(tester);

      expect(
        tester.widget<FilledButton>(find.byType(FilledButton)).onPressed,
        isNull,
        reason: 'a space needs a name',
      );
      await tester.enterText(find.widgetWithText(TextField, 'Name'), 'Flat 7C');
      await tester.tap(find.text('Trip'));
      await _addPerson(tester, '098000 00009', 'Xavier');
      expect(find.text('Xavier'), findsOne);
      expect(find.text('+91 98000 00009'), findsOne);
      await _tapCreate(tester);

      expect(find.text('New space'), findsNothing);
      expect(find.text('Flat 7C'), findsOne);
      expect(find.text("Xavier hasn't joined yet"), findsOne);
      expect(repository.calls, hasLength(1));
      expect(repository.calls.single, endsWith(' Flat 7C +919800000009'));
      expect(repository.spaces.last.kind, SpaceKind.trip);
    });

    testWidgets('a retry after a failure reuses the idempotency key', (
      tester,
    ) async {
      final repository = FakeSpacesRepository(spacesList);
      await _pump(tester, repository);
      await _openSheet(tester);
      await tester.enterText(find.widgetWithText(TextField, 'Name'), 'Flat 7C');
      repository.failure = Exception('offline');

      await _tapCreate(tester);
      expect(find.textContaining("We couldn't create the space"), findsOne);
      expect(find.text('New space'), findsOne);

      await _tapCreate(tester);
      expect(find.text('New space'), findsNothing);
      final [first, second] = repository.calls;
      expect(first.split(' ').first, second.split(' ').first);
      expect(find.text('Flat 7C'), findsOne);
    });

    testWidgets('a reopened sheet gets a new key', (tester) async {
      final repository = FakeSpacesRepository(const []);
      await _pump(tester, repository);
      for (final name in ['A', 'B']) {
        await _openSheet(tester);
        await tester.enterText(find.widgetWithText(TextField, 'Name'), name);
        await _tapCreate(tester);
      }
      final [a, b] = repository.calls;
      expect(a.split(' ').first, isNot(b.split(' ').first));
      expect(repository.spaces, hasLength(2));
    });

    testWidgets('a key reused with other details says it was saved', (
      tester,
    ) async {
      final repository = FakeSpacesRepository(spacesList);
      await _pump(tester, repository);
      await _openSheet(tester);
      await tester.enterText(find.widgetWithText(TextField, 'Name'), 'Flat 7C');
      repository.failure = const IdempotencyConflict() as Exception;

      await _tapCreate(tester);
      expect(find.textContaining('already saved'), findsOne);
    });

    testWidgets('numbers must be phone numbers, once each', (tester) async {
      await _pump(tester, FakeSpacesRepository(spacesList));
      await _openSheet(tester);

      await _addPerson(tester, '12345', 'Bad');
      expect(find.text('Enter a mobile number, like 98765 43210'), findsOne);
      expect(find.text('Bad'), findsOne, reason: 'the field keeps the name');

      await _addPerson(tester, '+44 7700 900123', 'Tom');
      expect(find.text('Tom'), findsOne);
      await _addPerson(tester, '+447700900123', 'Again');
      expect(find.text('+447700900123 is already added'), findsOne);

      await tester.tap(find.byTooltip('Remove Tom'));
      await tester.pumpAndSettle();
      expect(find.text('Tom'), findsNothing);
    });

    for (final mine in ['98765 43210', '+91 98765 43210', '09876543210']) {
      testWidgets('your own number is refused: $mine', (tester) async {
        await _pump(tester, FakeSpacesRepository(const []));
        await _openSheet(tester);
        await _addPerson(tester, mine, 'Me');
        expect(
          find.text("That's your number. You're in the space already."),
          findsOne,
        );
        expect(find.byTooltip('Remove Me'), findsNothing);
      });
    }

    testWidgets('a person without a name is shown by number', (tester) async {
      final repository = FakeSpacesRepository(const []);
      await _pump(tester, repository);
      await _openSheet(tester);
      await tester.enterText(find.widgetWithText(TextField, 'Name'), 'Club');
      await _addPerson(tester, '9800000009', '');
      expect(find.text('+919800000009'), findsOne);
      await _tapCreate(tester);
      expect(repository.spaces.single.others.single.name, '+919800000009');
    });
  });

  group('Home refreshes after a space is created', () {
    test('creating bumps the ledger revision Home watches', () async {
      final home = FakeHomeRepository(homeEmpty);
      final c = ProviderContainer(
        overrides: [
          homeRepositoryProvider.overrideWithValue(home),
          spacesRepositoryProvider.overrideWithValue(
            FakeSpacesRepository(const []),
          ),
        ],
      );
      addTearDown(c.dispose);
      expect((await c.read(homeProvider.future)).isEmpty, isTrue);
      final sub = c.listen(homeProvider, (_, _) {});
      addTearDown(sub.close);

      home.data = homeMain;
      await c
          .read(spacesProvider.notifier)
          .create(
            name: 'Flat 402',
            kind: SpaceKind.flat,
            members: const [],
            idempotencyKey: 'k1',
          );

      expect((await c.read(homeProvider.future)).spaces, isNotEmpty);
    });

    testWidgets('Home → create on Spaces → Home shows it', (tester) async {
      final home = FakeHomeRepository(homeEmpty);
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            sessionProvider.overrideWith(
              () => FakeSessionNotifier(fakeSession),
            ),
            homeRepositoryProvider.overrideWithValue(home),
            spacesRepositoryProvider.overrideWithValue(
              FakeSpacesRepository(const []),
            ),
          ],
          child: const SettloApp(),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Record a loan'), findsOne);
      Finder tab(String label) => find.descendant(
        of: find.byType(SGlassTabBar),
        matching: find.text(label),
      );

      await tester.tap(tab('Spaces'));
      await tester.pumpAndSettle();
      await _openSheet(tester);
      await tester.enterText(
        find.widgetWithText(TextField, 'Name'),
        'Flat 402',
      );
      home.data = homeMain;
      await _tapCreate(tester);
      await tester.tap(tab('Home'));
      await tester.pumpAndSettle();

      expect(find.text('Record a loan'), findsNothing);
      expect(find.text('Rahul, Priya'), findsOne);
    });
  });

  group('Space · empty', () {
    Future<GoRouter> pumpEmpty(WidgetTester tester) => _pump(
      tester,
      FakeSpacesRepository([spaceEmpty]),
      initialLocation: SettloRoutes.space(spaceEmpty.id),
    );

    testWidgets('says the others see expenses when they join', (tester) async {
      await pumpEmpty(tester);

      expect(find.text('NOVEMBER'), findsOne);
      expect(
        find.text(
          'No expenses yet. You can add them now — Rahul and Priya will '
          'see everything the moment their numbers are verified.',
        ),
        findsOne,
      );
      expect(find.text('1 OF 3 JOINED'), findsOne);
      expect(find.text('You'), findsOne);
      expect(find.text('admin'), findsOne);
      expect(find.text('+91\u00A0•••\u00A00044 · not joined yet'), findsOne);
      expect(find.text('+91\u00A0•••\u00A00010 · not joined yet'), findsOne);
    });

    testWidgets('a space with expenses is not empty', (tester) async {
      await _pump(
        tester,
        FakeSpacesRepository(spacesList),
        initialLocation: SettloRoutes.space('s1'),
      );
      expect(find.text('NOVEMBER'), findsNothing);
      expect(find.byType(SpaceDetailView), findsOne);
    });

    for (final (label, location) in [
      ('Add first expense', SettloRoutes.addExpenseIn('s9')),
      ('Add rent as a monthly expense', SettloRoutes.addExpenseIn('s9')),
      ('Add your UPI ID so settle-ups are one tap', SettloRoutes.profile),
    ]) {
      testWidgets('$label goes to $location', (tester) async {
        final router = await pumpEmpty(tester);
        await tester.ensureVisible(find.text(label));
        await tester.pumpAndSettle();
        await tester.tap(find.text(label));
        await tester.pumpAndSettle();
        expect(router.state.uri.toString(), location);
      });
    }

    testWidgets('Back returns to the list', (tester) async {
      final router = await pumpEmpty(tester);
      await tester.tap(find.byTooltip('Back'));
      await tester.pumpAndSettle();
      expect(router.state.uri.toString(), SettloRoutes.spaces);
    });
  });

  group('Space with expenses', () {
    Future<(GoRouter, FakeSpaceLedgerRepository)> pumpSpace(
      WidgetTester tester, {
      String spaceId = 's1',
      bool balances = false,
    }) async {
      final ledger = FakeSpaceLedgerRepository();
      final router = await _pump(
        tester,
        FakeSpacesRepository(spacesList),
        initialLocation: balances
            ? SettloRoutes.spaceBalances(spaceId)
            : SettloRoutes.space(spaceId),
        ledger: ledger,
      );
      return (router, ledger);
    }

    Future<void> openExpense(WidgetTester tester, String description) async {
      await tester.ensureVisible(find.text(description));
      await tester.pumpAndSettle();
      await tester.tap(find.text(description));
      await tester.pumpAndSettle();
    }

    testWidgets('expenses are grouped by day under the month', (tester) async {
      await pumpSpace(tester);

      expect(find.text('YOU ARE OWED'), findsOne);
      expect(find.text('November'), findsOne);
      expect(find.text('Daily spend · Nov'), findsOne);
      expect(find.text('₹4,140 today'), findsOne);
      expect(find.text('Today'), findsOne);
      expect(find.text('Yesterday'), findsOne);
      expect(find.text('you paid · split 3 ways'), findsWidgets);
      expect(find.text('Priya paid · split 3 ways'), findsWidgets);
      await _scrollToEnd(tester);
      for (final day in ['Thu 5 Nov', 'Mon 2 Nov', 'Sun 1 Nov']) {
        expect(find.text(day), findsOne, reason: day);
      }
      expect(find.text('Milk · Nov'), findsOne);
    });

    testWidgets('the tabs and actions go where they say', (tester) async {
      for (final (label, location) in [
        ('Balances', SettloRoutes.spaceBalances('s1')),
        ('Activity', SettloRoutes.activity),
        ('Add expense', SettloRoutes.addExpenseIn('s1')),
        ('Settle up', SettloRoutes.settleWith('s1')),
      ]) {
        final (router, _) = await pumpSpace(tester);
        await tester.tap(
          find.descendant(
            of: find.byType(SpaceDetailView),
            matching: find.text(label),
          ),
        );
        await tester.pumpAndSettle();
        expect(router.state.uri.toString(), location, reason: label);
      }
      final (router, _) = await pumpSpace(tester, balances: true);
      await tester.tap(find.text('Expenses'));
      await tester.pumpAndSettle();
      expect(router.state.uri.toString(), SettloRoutes.space('s1'));
    });

    testWidgets('balances: who paid against a fair share, then settling', (
      tester,
    ) async {
      final (router, _) = await pumpSpace(tester, balances: true);

      expect(find.text('WHO PAID VS FAIR SHARE · NOV'), findsOne);
      expect(find.text('₹6,150 EACH'), findsOne);
      expect(
        [
          for (final bar in tester.widgetList<FairShareBar>(
            find.byType(FairShareBar),
          ))
            (bar.name, bar.paid, bar.fairShare, bar.monthTotal),
        ],
        const [
          ('You', Paise.rupees(9000), Paise.rupees(6150), Paise.rupees(18450)),
          (
            'Rahul',
            Paise.rupees(5400),
            Paise.rupees(6150),
            Paise.rupees(18450),
          ),
          (
            'Priya',
            Paise.rupees(4050),
            Paise.rupees(6150),
            Paise.rupees(18450),
          ),
        ],
      );
      expect(find.text('+₹2,850'), findsOne);
      expect(find.text('−₹2,100'), findsOne);
      expect(find.text('2 PAYMENTS'), findsOne);
      expect(find.text('Priya pays you'), findsOne);
      expect(find.text('Rahul pays you'), findsOne);
      await _scrollToEnd(tester);
      expect(find.text('BY CATEGORY · NOV'), findsOne);
      expect(find.text('Household'), findsOne);
      expect(find.text('No category'), findsOne);

      await tester.tap(find.text('Remind').first);
      await tester.pumpAndSettle();
      expect(
        router.state.uri.toString(),
        SettloRoutes.settleWith('s1', memberId: 'm3'),
      );
    });

    testWidgets('paid and fair share are read in rupees', (tester) async {
      final semantics = tester.ensureSemantics();
      await pumpSpace(tester, balances: true);

      const you =
          'You paid nine thousand rupees, fair share six thousand one hundred '
          'fifty rupees, two thousand eight hundred fifty rupees more than '
          'their share';
      const priya =
          'Priya paid four thousand fifty rupees, fair share six thousand one '
          'hundred fifty rupees, two thousand one hundred rupees less than '
          'their share';
      for (final label in [you, priya]) {
        expect(find.bySemanticsLabel(label), findsOne, reason: label);
      }
      expect(find.bySemanticsLabel(RegExp('₹|paise')), findsNothing);
      semantics.dispose();
    });

    testWidgets('only the creator or an owner sees edit and delete', (
      tester,
    ) async {
      final semantics = tester.ensureSemantics();
      // In Goa trip you are not an owner.
      await pumpSpace(tester, spaceId: 's2');

      expect(find.bySemanticsLabel(RegExp('Shack lunch')), isNot(findsNothing));
      expect(
        tester.getSemantics(find.text('Shack lunch')),
        isNot(isSemantics(hasTapAction: true)),
      );
      await openExpense(tester, 'Shack lunch');
      expect(find.text('Save changes'), findsNothing);

      await openExpense(tester, 'Scooters');
      expect(find.text('Save changes'), findsOne);
      semantics.dispose();
    });

    testWidgets('an edit saves through update_expense with one key', (
      tester,
    ) async {
      final (_, ledger) = await pumpSpace(tester);
      await openExpense(tester, 'Groceries · BigBasket');
      expect(find.text('Edit expense · Flat 402'), findsOne);

      await tester.enterText(find.byType(TextField).first, '2,000.50');
      await tester.enterText(find.byType(TextField).last, 'Groceries');
      ledger.failure = Exception('offline');
      await tester.tap(find.text('Save changes'));
      await tester.pumpAndSettle();
      expect(
        find.text(
          "We couldn't save that. Check your connection and try again.",
        ),
        findsOne,
      );

      await tester.tap(find.text('Save changes'));
      await tester.pumpAndSettle();
      expect(find.text('Save changes'), findsNothing);
      final [first, retry] = ledger.calls;
      expect(first, retry, reason: 'a retry reuses the key');
      expect(first, matches(RegExp(r'^update \S{36} e1 Groceries 200050$')));
      expect(find.text('Groceries'), findsOne);
      expect(find.text('₹2,000.50'), findsOne);
    });

    testWidgets('editing a settle-up leaves the spend unchanged', (
      tester,
    ) async {
      final ledger = FakeSpaceLedgerRepository({'s1': flatLedgerWithSettleUp});
      await _pump(
        tester,
        FakeSpacesRepository(spacesList),
        initialLocation: SettloRoutes.space('s1'),
        ledger: ledger,
      );
      expect(find.text('settle-up'), findsOne);
      expect(find.text('₹4,140 today'), findsOne, reason: 'not spending');

      await openExpense(tester, 'Rahul paid you back');
      await tester.enterText(find.byType(TextField).last, 'Paid back in cash');
      await tester.tap(find.text('Save changes'));
      await tester.pumpAndSettle();

      final [edited, ...] = (await ledger.load('s1')).expenses;
      expect(
        (edited.description, edited.isSettlement),
        ('Paid back in cash', true),
      );
      expect(find.text('settle-up'), findsOne);
      await tester.drag(find.byType(ListView), const Offset(0, 2000));
      await tester.pumpAndSettle();
      expect(find.text('₹4,140 today'), findsOne, reason: 'still not spending');
    });

    testWidgets('a split by amounts keeps its amount', (tester) async {
      await pumpSpace(tester);
      await openExpense(tester, 'Wifi · Airtel');

      expect(find.byType(TextField), findsOne, reason: 'description only');
      expect(find.textContaining('its amount stays as it is'), findsOne);
    });

    testWidgets('delete asks once more, then removes it', (tester) async {
      final (_, ledger) = await pumpSpace(tester);
      await openExpense(tester, 'Electricity');

      await tester.tap(find.text('Delete expense'));
      await tester.pumpAndSettle();
      expect(ledger.calls, isEmpty);
      await tester.tap(find.text('Tap again to delete'));
      await tester.pumpAndSettle();

      expect(ledger.calls.single, matches(RegExp(r'^delete \S{36} e2$')));
      expect(find.text('Electricity'), findsNothing);
    });
  });

  group('every control is at least 44x44pt', () {
    for (final (name, spaces, location, sheet) in [
      ('Spaces', spacesList, SettloRoutes.spaces, false),
      ('Space · empty', [spaceEmpty], SettloRoutes.space('s9'), false),
      ('Space · expenses', spacesList, SettloRoutes.space('s1'), false),
      ('Space · balances', spacesList, SettloRoutes.spaceBalances('s1'), false),
      ('New space', spacesList, SettloRoutes.spaces, true),
    ]) {
      testWidgets('$name meets the iOS tap target guideline', (tester) async {
        final semantics = tester.ensureSemantics();
        await _pump(
          tester,
          FakeSpacesRepository(spaces),
          initialLocation: location,
        );
        if (sheet) {
          await _openSheet(tester);
          await _addPerson(tester, '9800000009', 'Xavier');
        }
        await expectLater(tester, meetsGuideline(iOSTapTargetGuideline));
        await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));
        if (!sheet) {
          await _scrollToEnd(tester);
          await expectLater(tester, meetsGuideline(iOSTapTargetGuideline));
        }
        semantics.dispose();
      });
    }
  });

  testWidgets('amounts are announced in rupees', (tester) async {
    final semantics = tester.ensureSemantics();
    await _pump(tester, FakeSpacesRepository(spacesList));
    for (final label in [
      RegExp(
        'Flat 402\nRahul, Priya\nplus two thousand eight hundred fifty '
        'rupees\nowed to you\nYou paid 49% of eighteen thousand four '
        'hundred fifty rupees\nfair share 33%',
      ),
      RegExp(
        'Goa trip\n5 people\nminus three thousand six hundred fifty rupees',
      ),
      RegExp('one thousand two hundred rupees in Goa trip is recorded'),
    ]) {
      expect(find.bySemanticsLabel(label), findsOne, reason: '$label');
    }
    expect(find.bySemanticsLabel(RegExp('₹|paise')), findsNothing);
    semantics.dispose();
  });

  // Flutter reports any overflow to the test binding, which fails the
  // test; nothing here consumes it (docs/release.md).
  group('fits 360x800 without overflow', () {
    for (final (name, spaces, location, sheet) in [
      ('Spaces', spacesList, SettloRoutes.spaces, false),
      ('Space · empty', [spaceEmpty], SettloRoutes.space('s9'), false),
      ('Space · expenses', spacesList, SettloRoutes.space('s1'), false),
      ('Space · balances', spacesList, SettloRoutes.spaceBalances('s1'), false),
      ('New space', spacesList, SettloRoutes.spaces, true),
    ]) {
      testWidgets(name, (tester) async {
        await _pump(
          tester,
          FakeSpacesRepository(spaces),
          initialLocation: location,
          device: SettloGoldenDevices.compact360,
        );
        if (sheet) {
          await _openSheet(tester);
          await tester.enterText(
            find.widgetWithText(TextField, 'Name'),
            'A rather long name for a shared flat',
          );
          await _addPerson(tester, '9800000009', 'Xavier Fernandes-Iyer');
          await _addPerson(tester, '9800000010', 'Priya');
          await tester.ensureVisible(find.text('Create space'));
          await tester.pumpAndSettle();
        } else {
          if (find.text('Add expense').evaluate().isNotEmpty) {
            expect(
              tester
                  .renderObject<RenderParagraph>(find.text('Add expense'))
                  .didExceedMaxLines,
              isFalse,
              reason: 'the label is not cut short',
            );
          }
          await _scrollToEnd(tester);
        }
      });
    }
  });
}
