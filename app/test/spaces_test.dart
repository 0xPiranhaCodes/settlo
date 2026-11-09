import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:settlo/shell.dart';
import 'package:settlo_core/settlo_core.dart';
import 'package:settlo_spaces/settlo_spaces.dart';
import 'package:settlo_test_support/golden.dart';

import 'support/fake_spaces.dart';

/// Pumps the Spaces tab in the shell at [initialLocation] with
/// [repository], inside a router whose other routes record where the
/// screen sent the user.
Future<GoRouter> _pump(
  WidgetTester tester,
  FakeSpacesRepository repository, {
  String initialLocation = SettloRoutes.spaces,
  GoldenDevice device = SettloGoldenDevices.canvas390,
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
          ),
        ],
      ),
      for (final path in [SettloRoutes.addExpense, SettloRoutes.profile])
        GoRoute(path: path, builder: (_, state) => Text('at ${state.uri}')),
    ],
  );
  addTearDown(router.dispose);
  await tester.pumpWidget(
    ProviderScope(
      overrides: [spacesRepositoryProvider.overrideWithValue(repository)],
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
      expect(find.byType(SPlaceholderScreen), findsOne);
    });

    for (final (label, location) in [
      ('Add first expense', SettloRoutes.addExpense),
      ('Add rent as a monthly expense', SettloRoutes.addExpense),
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

  group('every control is at least 44x44pt', () {
    for (final (name, spaces, location, sheet) in [
      ('Spaces', spacesList, SettloRoutes.spaces, false),
      ('Space · empty', [spaceEmpty], SettloRoutes.space('s9'), false),
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
          await _scrollToEnd(tester);
        }
      });
    }
  });
}
