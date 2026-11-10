import 'dart:async';
import 'dart:ui' show SemanticsAction;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:settlo/shell.dart';
import 'package:settlo_balances/settlo_balances.dart';
import 'package:settlo_core/settlo_core.dart';
import 'package:settlo_test_support/golden.dart';

import 'support/fake_activity.dart';
import 'support/fake_home.dart';

/// Pumps Home in the shell with [repository], inside a router whose other
/// routes record where Home sent the user.
Future<GoRouter> _pump(
  WidgetTester tester,
  FakeHomeRepository repository, {
  GoldenDevice device = SettloGoldenDevices.canvas390,
  double textScaleFactor = 1,
  FakeActivityRepository? activityRepository,
  bool disableAnimations = false,
}) async {
  await loadSettloFonts();
  tester.view
    ..physicalSize = device.size
    ..devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  tester.platformDispatcher.textScaleFactorTestValue = textScaleFactor;
  tester.platformDispatcher.accessibilityFeaturesTestValue =
      FakeAccessibilityFeatures(disableAnimations: disableAnimations);
  addTearDown(() {
    tester.platformDispatcher
      ..clearTextScaleFactorTestValue()
      ..clearAccessibilityFeaturesTestValue();
  });
  final router = GoRouter(
    initialLocation: SettloRoutes.home,
    routes: [
      GoRoute(
        path: SettloRoutes.home,
        builder: (_, _) => SettloShell(
          currentIndex: 0,
          onTabSelected: (_) {},
          child: const HomeScreen(),
        ),
      ),
      for (final path in [
        SettloRoutes.spaces,
        SettloRoutes.spacePattern,
        SettloRoutes.loans,
        SettloRoutes.newLoan,
        SettloRoutes.confirmRepaymentPattern,
        SettloRoutes.loanPattern,
        SettloRoutes.activity,
        SettloRoutes.profile,
        SettloRoutes.addExpense,
        SettloRoutes.settle,
      ])
        GoRoute(path: path, builder: (_, state) => Text('at ${state.uri}')),
    ],
  );
  addTearDown(router.dispose);
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        homeRepositoryProvider.overrideWithValue(repository),
        activityRepositoryProvider.overrideWithValue(
          activityRepository ?? FakeActivityRepository(),
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

/// Scrolls Home to its end, so every row has been laid out.
Future<void> _scrollToEnd(WidgetTester tester) async {
  await tester.drag(find.byType(CustomScrollView), const Offset(0, -2000));
  await tester.pumpAndSettle();
}

void main() {
  group('homeProvider', () {
    ProviderContainer container(FakeHomeRepository repository) {
      final c = ProviderContainer(
        overrides: [homeRepositoryProvider.overrideWithValue(repository)],
      );
      addTearDown(c.dispose);
      return c;
    }

    test('loads Home and totals balances in paise', () async {
      final home = await container(FakeHomeRepository(homeMain))
          .read(homeProvider.future);
      expect(home.owed.value, 67785000);
      expect(home.owe.value, 365000);
      expect(home.net.value, 67420000);
      expect(home.monthSpend.value, 1845000);
    });

    test('accepting a claim reloads it into the balances', () async {
      final repository = FakeHomeRepository(homeFound);
      final c = container(repository);
      await c.read(homeProvider.future);

      await c
          .read(homeProvider.notifier)
          .accept(homeFound.claims.first, idempotencyKey: 'k1');

      final home = c.read(homeProvider).requireValue;
      expect(repository.calls, ['accept m1']);
      expect(home.claims.map((x) => x.id), ['m2', 'l2']);
      expect(home.spaces.single.balance.value, -75000);
    });

    test('rejecting a claim drops it without a balance', () async {
      final repository = FakeHomeRepository(homeFound);
      final c = container(repository);
      await c.read(homeProvider.future);

      await c
          .read(homeProvider.notifier)
          .reject(homeFound.claims.last, idempotencyKey: 'k1');

      final home = c.read(homeProvider).requireValue;
      expect(repository.calls, ['reject l2']);
      expect(home.claims.map((x) => x.id), ['m1', 'm2']);
      expect(home.loans, isEmpty);
    });

    test('a refused claim call throws and leaves Home as it was', () async {
      final repository = FakeHomeRepository(homeFound);
      final c = container(repository);
      await c.read(homeProvider.future);
      repository.failure = Exception('42501');

      await expectLater(
        c
            .read(homeProvider.notifier)
            .accept(homeFound.claims.first, idempotencyKey: 'k1'),
        throwsException,
      );
      expect(c.read(homeProvider).requireValue.claims, hasLength(3));
    });
  });

  group('Home', () {
    testWidgets('shows the net position, stats and both cards', (tester) async {
      await _pump(tester, FakeHomeRepository(homeMain));

      expect(find.text('owed to you across 2 spaces and 1 loan'), findsOne);
      expect(find.text('Nov spend'), findsOne);
      expect(find.text('Rahul, Priya'), findsOne);
      expect(find.text('5 people'), findsOne);
      expect(find.text('13 of 40 · next ₹25,000 on 5 Dec'), findsOne);
      await _scrollToEnd(tester);
      expect(find.text('RECENT ACTIVITY'), findsOne);
      expect(find.textContaining('Priya added'), findsOne);
    });

    testWidgets('accepting a claim moves it into the balances', (tester) async {
      final repository = FakeHomeRepository(
        HomeData(
          phone: homePhone,
          month: DateTime(2026, 11),
          claims: [homeFound.claims.first],
        ),
      );
      await _pump(tester, repository);
      expect(find.text('Your ledger was waiting'), findsOne);
      expect(find.text('Rahul says you owe ₹750 · 3 people'), findsOne);
      expect(find.text('NET POSITION · AFTER YOU REVIEW'), findsOne);
      expect(find.text('SPACES'), findsNothing);

      await tester.tap(find.text('Accept'));
      await tester.pumpAndSettle();

      expect(repository.calls, ['accept m1']);
      expect(find.text('Your ledger was waiting'), findsNothing);
      expect(find.text('NET POSITION'), findsOne);
      expect(find.text('you owe across 1 space'), findsOne);
      expect(find.text('SPACES'), findsOne);
      expect(find.text('Flat 402'), findsOne);
      expect(find.text('−₹750'), findsOne);
    });

    testWidgets("'This isn't me' removes the claim", (tester) async {
      final repository = FakeHomeRepository(homeFound);
      await _pump(tester, repository);

      await tester.ensureVisible(find.text("This isn't me").last);
      await tester.pumpAndSettle();
      await tester.tap(find.text("This isn't me").last);
      await tester.pumpAndSettle();

      expect(repository.calls, ['reject l2']);
      expect(find.text('Loan with Arjun'), findsNothing);
      expect(
        find.text(
          'Friends recorded 2 spaces against +91 98765 43210 '
          'before you joined. Review them — nothing is confirmed until you '
          'say so.',
        ),
        findsOne,
      );
    });

    for (final button in ['Accept', "This isn't me"]) {
      testWidgets('a no-pump double tap on "$button" answers once', (
        tester,
      ) async {
        final repository = FakeHomeRepository(homeFound);
        await _pump(tester, repository);

        // No pump between the taps, and the first answer still in flight.
        repository.gate = Completer();
        await tester.tap(find.text(button).first);
        await tester.tap(find.text(button).first, warnIfMissed: false);
        repository.gate!.complete();
        await tester.pumpAndSettle();

        expect(repository.calls, hasLength(1));
      });
    }

    for (final button in ['Accept', "This isn't me"]) {
      testWidgets('signing out while "$button" is queued says nothing', (
        tester,
      ) async {
        final repository = FakeHomeRepository(homeFound);
        await _pump(tester, repository);

        // The tap is in flight when the session ends under it.
        repository.gate = Completer();
        await tester.tap(find.text(button).first);
        await tester.pump();
        repository
          ..failure = const SessionEnded()
          ..gate!.complete();
        await tester.pumpAndSettle();

        expect(tester.takeException(), isNull);
        expect(find.byType(SnackBar), findsNothing);
        expect(find.textContaining("couldn't"), findsNothing);
        expect(find.textContaining('SessionEnded'), findsNothing);
        expect(repository.calls, isEmpty);
      });
    }

    testWidgets('a retry reuses its key; each button has its own', (
      tester,
    ) async {
      final repository = FakeHomeRepository(homeFound);
      await _pump(tester, repository);
      repository.failure = Exception('offline');

      await tester.tap(find.text('Accept').first);
      await tester.pump();
      await tester.tap(find.text('Accept').first);
      await tester.pump();
      await tester.tap(find.text("This isn't me").first);
      await tester.pump();

      final [first, retry, other] = repository.keys;
      expect(retry, first);
      expect(other, isNot(first));
    });

    testWidgets('a refused claim says so and keeps the claim', (tester) async {
      final repository = FakeHomeRepository(homeFound);
      await _pump(tester, repository);
      repository.failure = Exception('offline');

      await tester.tap(find.text('Accept').first);
      await tester.pump();

      expect(find.textContaining("We couldn't save that"), findsOne);
      expect(find.text('Flat 402'), findsOne);
    });

    testWidgets('a failed load keeps the hero in place and says why', (
      tester,
    ) async {
      await _pump(tester, FakeHomeRepository(homeMain)..failure = Exception());

      expect(find.text('NET POSITION'), findsOne);
      expect(find.textContaining("We couldn't load your balances"), findsOne);
    });

    testWidgets('pulling down reloads', (tester) async {
      final repository = FakeHomeRepository(homeEmpty);
      final activity = FakeActivityRepository();
      await _pump(tester, repository, activityRepository: activity);
      expect(find.text('Start a space'), findsOne);
      final activityReads = activity.calls.length;

      repository.data = homeMain;
      await tester.fling(
        find.byType(CustomScrollView),
        const Offset(0, 400),
        1000,
      );
      await tester.pumpAndSettle();

      expect(find.text('Flat 402'), findsOne);
      expect(activity.calls.length, greaterThan(activityReads));
    });

    for (final (data, label, location) in [
      (homeMain, 'Add expense', SettloRoutes.addExpense),
      (homeMain, 'Settle up', SettloRoutes.settle),
      (homeMain, 'SEE ALL', SettloRoutes.spaces),
      (homeMain, 'Flat 402', SettloRoutes.space('s1')),
      (homeMain, 'Arjun · interest free', SettloRoutes.loan('l1')),
      (homeEmpty, 'Start a space', SettloRoutes.spaces),
      (homeEmpty, 'Record a loan', SettloRoutes.newLoan),
    ]) {
      testWidgets('$label goes to $location', (tester) async {
        final router = await _pump(tester, FakeHomeRepository(data));
        await tester.ensureVisible(find.text(label));
        await tester.pumpAndSettle();
        await tester.tap(find.text(label));
        await tester.pumpAndSettle();
        expect(router.state.uri.toString(), location);
      });
    }

    for (final (label, target, location) in [
      ('Notifications', find.byTooltip('Notifications'), SettloRoutes.activity),
      ('Profile', find.byTooltip('Profile'), SettloRoutes.profile),
    ]) {
      testWidgets('$label goes to $location', (tester) async {
        final router = await _pump(tester, FakeHomeRepository(homeMain));
        await tester.tap(target);
        await tester.pumpAndSettle();
        expect(router.state.uri.toString(), location);
      });
    }

    testWidgets('pending repayment opens its confirmation receipt', (
      tester,
    ) async {
      final router = await _pump(tester, FakeHomeRepository(homeMain));
      await _scrollToEnd(tester);
      await tester.tap(find.text('₹25,000 · Review repayment'));
      await tester.pumpAndSettle();
      expect(router.state.uri.toString(), SettloRoutes.confirmRepayment('r3'));
    });

    testWidgets('a borrowed, flexible loan reads from your side', (
      tester,
    ) async {
      await _pump(
        tester,
        FakeHomeRepository(
          HomeData(
            phone: homePhone,
            month: DateTime(2026, 11),
            spaces: const [
              HomeSpace(
                id: 's9',
                name: 'Solo',
                kind: SpaceKind.friend,
                balance: Paise.zero,
                people: [],
              ),
              HomeSpace(
                id: 's8',
                name: 'Club',
                kind: SpaceKind.other,
                balance: Paise.zero,
                people: ['A'],
              ),
            ],
            loans: const [
              HomeLoan(
                id: 'l9',
                counterparty: 'Arjun',
                youLent: false,
                outstanding: Paise.rupees(500),
              ),
              HomeLoan(
                id: 'l8',
                counterparty: 'Meera',
                youLent: true,
                outstanding: Paise.rupees(500),
                installmentsPaid: 1,
                installmentsTotal: 2,
              ),
            ],
          ),
        ),
      );
      expect(find.text('all settled across 2 spaces and 2 loans'), findsOne);
      await _scrollToEnd(tester);

      expect(find.text('Just you'), findsOne);
      expect(find.text('you borrowed · flexible repayments'), findsOne);
      expect(find.text('1 of 2'), findsOne);
    });
  });

  group('every control is at least 44x44pt', () {
    Future<void> expectTargets(WidgetTester tester, Finder finder) async {
      expect(finder, findsWidgets);
      for (final element in finder.evaluate()) {
        final size = tester.getSize(find.byWidget(element.widget));
        expect(size.width, greaterThanOrEqualTo(44), reason: '$finder');
        expect(size.height, greaterThanOrEqualTo(44), reason: '$finder');
      }
    }

    Finder tappable(String text, Type type) =>
        find.ancestor(of: find.text(text), matching: find.byType(type)).first;

    for (final (name, data) in [
      ('Home', homeMain),
      ('Home · empty', homeEmpty),
      ('Home · ledger found', homeFound),
    ]) {
      testWidgets('$name meets the iOS tap target guideline', (tester) async {
        final semantics = tester.ensureSemantics();
        await _pump(tester, FakeHomeRepository(data));
        await expectLater(tester, meetsGuideline(iOSTapTargetGuideline));
        await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));
        await _scrollToEnd(tester);
        // Pinned chrome clips the first visible row; audit its full hit box.
        expectSettloTapTargets(tester);
        semantics.dispose();
      });
    }

    testWidgets('header, See all and the loan row', (tester) async {
      await _pump(tester, FakeHomeRepository(homeMain));
      await expectTargets(tester, find.byType(IconButton));
      await expectTargets(tester, tappable('SEE ALL', GestureDetector));
      await expectTargets(
        tester,
        tappable('Arjun · interest free', SPressable),
      );
    });

    testWidgets('a single-line loan row still has a 44pt target', (
      tester,
    ) async {
      await _pump(
        tester,
        FakeHomeRepository(
          HomeData(
            phone: homePhone,
            month: DateTime(2026, 11),
            loans: const [
              HomeLoan(
                id: 'l1',
                counterparty: 'Arjun',
                youLent: true,
                outstanding: Paise.rupees(500),
                installmentsPaid: 1,
                installmentsTotal: 2,
              ),
            ],
          ),
        ),
      );
      await expectTargets(
        tester,
        tappable('Arjun · interest free', SPressable),
      );
    });

    testWidgets('claim actions', (tester) async {
      await _pump(tester, FakeHomeRepository(homeFound));
      await expectTargets(tester, find.widgetWithText(TextButton, 'Accept'));
      await expectTargets(
        tester,
        find.widgetWithText(TextButton, "This isn't me"),
      );
    });
  });

  testWidgets('amounts are announced in rupees beside their labels', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();
    await _pump(tester, FakeHomeRepository(homeMain));
    for (final label in [
      [
        'NET POSITION',
        'plus six lakh seventy-four thousand two hundred rupees',
        'owed to you across 2 spaces and 1 loan',
      ].join('\n'),
      [
        'Arjun',
        'Arjun · interest free',
        '13 of 40 · next twenty-five thousand rupees on 5 Dec',
        'six lakh seventy-five thousand rupees',
      ].join('\n'),
      [
        'You are owed',
        'six lakh seventy-seven thousand eight hundred fifty rupees',
      ].join('\n'),
      'You owe\nthree thousand six hundred fifty rupees',
      'Nov spend\neighteen thousand four hundred fifty rupees',
      'Flat 402\nRahul, Priya\nplus two thousand eight hundred fifty rupees',
    ]) {
      expect(find.bySemanticsLabel(label), findsOne, reason: label);
    }
    expect(find.bySemanticsLabel(RegExp('₹|paise')), findsNothing);
    semantics.dispose();
  });

  testWidgets('claims are announced in rupees', (tester) async {
    final semantics = tester.ensureSemantics();
    await _pump(tester, FakeHomeRepository(homeFound));
    expect(
      find.bySemanticsLabel(
        RegExp('Rahul says you owe seven hundred fifty rupees · 3 people'),
      ),
      findsOne,
    );
    expect(
      find.bySemanticsLabel(RegExp('Arjun says you lent ten lakh rupees')),
      findsOne,
    );
    expect(find.bySemanticsLabel(RegExp('₹—')), findsNothing);
    expect(find.bySemanticsLabel(RegExp('₹[0-9]|paise')), findsNothing);
    semantics.dispose();
  });

  // Flutter reports any overflow to the test binding, which fails the
  // test; nothing here consumes it (docs/release.md).
  group('fits 360x800 without overflow', () {
    for (final (name, data) in [
      ('Home', homeMain),
      ('Home · empty', homeEmpty),
      ('Home · ledger found', homeFound),
    ]) {
      testWidgets(name, (tester) async {
        await _pump(
          tester,
          FakeHomeRepository(data),
          device: SettloGoldenDevices.compact360,
        );
        await _scrollToEnd(tester);
        expect(find.byType(HomeScreen), findsOne);
      });
    }
  });

  testWidgets('empty Home fits at 200% text scaling', (tester) async {
    await _pump(
      tester,
      FakeHomeRepository(homeEmpty),
      device: SettloGoldenDevices.compact360,
      textScaleFactor: 2,
    );
    await _scrollToEnd(tester);
    expect(tester.takeException(), isNull);
  });

  testWidgets('populated Home fits at 200% text scaling', (tester) async {
    await _pump(
      tester,
      FakeHomeRepository(homeMain),
      device: SettloGoldenDevices.compact360,
      textScaleFactor: 2,
    );
    await _scrollToEnd(tester);
    expect(find.byType(HomeScreen), findsOneWidget);
  });

  testWidgets('empty action cards expose a semantic tap action', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();
    await _pump(tester, FakeHomeRepository(homeEmpty));
    for (final label in ['Start a space', 'Record a loan']) {
      final data = tester
          .getSemantics(find.bySemanticsLabel(label))
          .getSemanticsData();
      expect(data.hasAction(SemanticsAction.tap), isTrue, reason: label);
    }
    semantics.dispose();
  });

  testWidgets('Reduce Motion makes Home press feedback immediate', (
    tester,
  ) async {
    await _pump(tester, FakeHomeRepository(homeEmpty), disableAnimations: true);
    final action = find.bySemanticsLabel('Start a space');
    final gesture = await tester.startGesture(tester.getCenter(action));
    await tester.pump();
    final scale = tester.widget<AnimatedScale>(
      find.descendant(of: action, matching: find.byType(AnimatedScale)),
    );
    expect(scale.duration, Duration.zero);
    expect(scale.scale, 1);
    await gesture.up();
    await tester.pumpAndSettle();
  });
}
