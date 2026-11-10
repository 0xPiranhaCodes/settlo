import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:settlo_core/settlo_core.dart';
import 'package:settlo_settle/settlo_settle.dart';
import 'package:settlo_test_support/golden.dart';

import 'support/fake_settle.dart';
import 'support/fake_spaces.dart';

/// What the sheets asked the OS to open, and what the OS answers.
class _Links {
  final opened = <Uri>[];
  bool answer = true;

  Future<bool> open(Uri uri) async {
    opened.add(uri);
    return answer;
  }
}

typedef _Harness = ({
  GoRouter router,
  FakeSpacesRepository spaces,
  SettlingExpensesRepository expenses,
  _Links links,
});

/// Home with Settle up pushed over it at [location].
Future<_Harness> _pump(
  WidgetTester tester, {
  String location = SettloRoutes.settle,
  List<SpaceSummary>? spaces,
  bool realUpi = false,
}) async {
  await loadSettloFonts();
  tester.view
    ..physicalSize = SettloGoldenDevices.compact360.size
    ..devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final repo = FakeSpacesRepository(spaces ?? settleSpaces());
  final expenses = SettlingExpensesRepository(repo);
  final links = _Links();
  final router = GoRouter(
    initialLocation: SettloRoutes.home,
    routes: [
      GoRoute(path: SettloRoutes.home, builder: (_, _) => const Text('Home')),
      ...settleRoutes,
    ],
  );
  addTearDown(router.dispose);
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        spacesRepositoryProvider.overrideWithValue(repo),
        expensesRepositoryProvider.overrideWithValue(expenses),
        openUrlProvider.overrideWithValue(links.open),
        if (!realUpi) openUpiProvider.overrideWithValue(links.open),
      ],
      child: MaterialApp.router(
        theme: SettloTheme.dark(),
        routerConfig: router,
      ),
    ),
  );
  await tester.pumpAndSettle();
  unawaited(router.push(location));
  await tester.pumpAndSettle();
  return (router: router, spaces: repo, expenses: expenses, links: links);
}

/// Reloads the balances, as the app does when the payee answers.
Future<void> _reload(WidgetTester tester) async {
  ProviderScope.containerOf(tester.element(find.byType(Navigator).last))
      .invalidate(settleSpacesProvider);
  await tester.pumpAndSettle();
}

Future<void> _tap(WidgetTester tester, String text) async {
  await tester.tap(find.text(text));
  await tester.pumpAndSettle();
}

/// The channel `MainActivity` answers (packages/platform).
const upiChooserChannel = MethodChannel('app.settlo/upi');

void main() {
  testWidgets('settle up: both payments, then zero once Kabir confirms', (
    tester,
  ) async {
    final h = await _pump(tester);
    expect(find.text('2 PAYMENTS'), findsOne);
    expect(find.text('Priya pays you'), findsOne);

    // Pay side: the UPI app opens, nothing is recorded until you say so.
    await _tap(tester, 'You pay Kabir');
    expect(find.text('Settle up · Goa trip'), findsOne);
    await _tap(tester, 'Pay ₹3,650 via UPI');
    expect(
      h.links.opened.single,
      upiPayUri(
        payee: 'kabir@oksbi',
        name: 'Kabir',
        amount: const Paise.rupees(3650),
        note: 'Settlo: Goa trip',
      ),
    );
    expect(find.text('Did you pay Kabir ₹3,650?'), findsOne);
    expect(h.expenses.calls, isEmpty);
    await _tap(tester, 'Not yet');
    expect(h.expenses.calls, isEmpty);

    // A failed save keeps the sheet and its key; the retry reuses it.
    await _tap(tester, 'Pay ₹3,650 via UPI');
    h.expenses.failures.add(Exception('offline'));
    await _tap(tester, 'Yes, I paid');
    expect(find.textContaining("We couldn't record it."), findsOne);
    await _tap(tester, 'Yes, I paid');
    final [first, retry] = h.expenses.calls;
    expect(retry.key, first.key);
    final e = retry.expense;
    expect(
      (e.spaceId, e.isSettlement, e.splitType),
      ('s2', true, SplitType.exact),
    );
    expect(e.payers, {'m4': const Paise.rupees(3650)});
    expect(
      [for (final s in e.splits) (s.memberId, s.amount)],
      [('m5', const Paise.rupees(3650))],
    );

    // Back on the list, which reloaded: only Priya's payment is left to
    // make; yours to Kabir waits for him (#78) and is not offered again.
    expect(find.text('1 PAYMENT'), findsOne);
    expect(find.text('You pay Kabir'), findsNothing);
    expect(find.text('Waiting for Kabir to confirm'), findsOne);

    // Request side, paid in cash.
    await _tap(tester, 'Priya pays you');
    expect(find.text('Settle up · Flat 402'), findsOne);
    await _tap(tester, 'Record cash or bank payment');
    await _tap(tester, 'Record payment');
    expect(h.expenses.calls, hasLength(2));
    expect(find.text('Did Priya pay you ₹2,100?'), findsOne);
    await _tap(tester, 'Yes, Priya paid');
    expect(h.expenses.calls.last.expense.payers, {
      'm3': const Paise.rupees(2100),
    });

    // Recorded by the payee, Priya's counts at once; yours waits.
    expect(find.text('Waiting for Kabir to confirm'), findsOne);
    expect(find.text("You're all settled up."), findsNothing);
    h.expenses.answer('s2', 'm5', confirmed: true);
    await _reload(tester);
    expect(find.text("You're all settled up."), findsOne);
    expect([
      for (final s in h.spaces.spaces)
        for (final m in s.members) m.balance,
    ], everyElement(Paise.zero));
    expect(h.links.opened, hasLength(2));
  });

  testWidgets('paid: the row waits for the payee; disputed: Pay returns', (
    tester,
  ) async {
    final h = await _pump(tester);
    await _tap(tester, 'You pay Kabir');
    await _tap(tester, 'I already paid in cash');
    await _tap(tester, 'Yes, I paid');

    expect(find.text('You pay Kabir'), findsNothing);
    expect(find.text('Waiting for Kabir to confirm'), findsOne);
    expect(
      h.spaces.spaces.last.you.balance,
      const Paise.rupees(-3650),
      reason: 'balances count only confirmed settle-ups',
    );

    // Opening SettlePay for Kabir again offers nothing to pay.
    unawaited(h.router.push(SettloRoutes.settlePayTo('s2', 'm5')));
    await tester.pumpAndSettle();
    // Native pushed pages keep the previous route offstage.
    expect(find.text('Waiting for Kabir to confirm'), findsOneWidget);
    expect(find.textContaining('via UPI'), findsNothing);
    expect(find.text('I already paid in cash'), findsNothing);
    h.router.pop();
    await tester.pumpAndSettle();

    // Kabir says it never arrived: the debt is back.
    h.expenses.answer('s2', 'm5', confirmed: false);
    await _reload(tester);
    expect(find.text('Waiting for Kabir to confirm'), findsNothing);
    expect(find.text('You pay Kabir'), findsOne);
    expect(h.expenses.calls, hasLength(1));
  });

  testWidgets('a double tap on Yes, I paid records once', (tester) async {
    final h = await _pump(
      tester,
      location: SettloRoutes.settlePayTo('s2', 'm5'),
    );
    await _tap(tester, 'I already paid in cash');
    // No pump between the taps, and the first save still in flight: the
    // button is not rebuilt disabled yet.
    h.expenses.gate = Completer();
    await tester.tap(find.text('Yes, I paid'));
    await tester.tap(find.text('Yes, I paid'));
    h.expenses.gate!.complete();
    await tester.pumpAndSettle();
    expect(h.expenses.calls, hasLength(1));
  });

  testWidgets('someone who left is never offered as payer or payee', (
    tester,
  ) async {
    const left =
        "Arun has left Goa trip, so a settle-up with them can't be recorded "
        'here.';
    final h = await _pump(tester, spaces: settleSpacesWithDeparted());
    expect(find.text('1 PAYMENT'), findsOne);
    expect(find.text('You pay Kabir'), findsOne);
    expect(find.text('You pay Arun'), findsNothing);
    expect(find.text(left), findsOne);

    // Settling with Kabir records only active members.
    await _tap(tester, 'You pay Kabir');
    await _tap(tester, 'I already paid in cash');
    await _tap(tester, 'Yes, I paid');
    final e = h.expenses.calls.single.expense;
    expect(e.payers.keys, ['m4']);
    expect([for (final s in e.splits) s.memberId], ['m5']);

    // Only the debt to Arun is left, and it is explained, not offered.
    expect(find.text(left), findsOne);
    expect(find.textContaining('PAYMENT'), findsNothing);

    // A link straight to Arun gets the same plain message.
    unawaited(h.router.push(SettloRoutes.settlePayTo('s2', 'm6')));
    await tester.pumpAndSettle();
    expect(find.text(left), findsWidgets);
    expect(find.textContaining('Pay ₹'), findsNothing);
    expect(h.expenses.calls, hasLength(1));
  });

  testWidgets('no UPI app: a plain message and nothing recorded', (
    tester,
  ) async {
    final h = await _pump(
      tester,
      location: SettloRoutes.settlePayTo('s2', 'm5'),
    );
    h.links.answer = false;
    await _tap(tester, 'Pay ₹3,650 via UPI');

    expect(find.textContaining("There's no UPI app on this phone."), findsOne);
    expect(find.text('Did you pay Kabir ₹3,650?'), findsNothing);
    expect(h.expenses.calls, isEmpty);
  });

  group('the UPI app', () {
    final upi = upiPayUri(
      payee: 'kabir@oksbi',
      name: 'Kabir',
      amount: const Paise.rupees(3650),
      note: 'Settlo: Goa trip',
    );
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    tearDown(() {
      debugDefaultTargetPlatformOverride = null;
      messenger.setMockMethodCallHandler(upiChooserChannel, null);
    });

    testWidgets('Android: always through the OS chooser', (tester) async {
      debugDefaultTargetPlatformOverride = TargetPlatform.android;
      final calls = <MethodCall>[];
      var installed = false;
      messenger.setMockMethodCallHandler(upiChooserChannel, (call) async {
        calls.add(call);
        return installed;
      });
      final h = await _pump(
        tester,
        location: SettloRoutes.settlePayTo('s2', 'm5'),
        realUpi: true,
      );

      // No UPI app: a plain message, nothing recorded.
      await _tap(tester, 'Pay ₹3,650 via UPI');
      expect(
        find.textContaining("There's no UPI app on this phone."),
        findsOne,
      );

      installed = true;
      await _tap(tester, 'Pay ₹3,650 via UPI');
      expect(
        [for (final c in calls) c.method],
        ['openWithChooser', 'openWithChooser'],
      );
      expect((calls.last.arguments as Map)['uri'], '$upi');
      expect(h.links.opened, isEmpty, reason: 'not url_launcher');
      expect(find.text('Did you pay Kabir ₹3,650?'), findsOne);
      expect(h.expenses.calls, isEmpty);
      debugDefaultTargetPlatformOverride = null;
    });

    testWidgets('iOS: opens upi:// directly, no chooser', (tester) async {
      debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
      var chooser = false;
      messenger.setMockMethodCallHandler(upiChooserChannel, (_) async {
        chooser = true;
        return true;
      });
      final h = await _pump(
        tester,
        location: SettloRoutes.settlePayTo('s2', 'm5'),
        realUpi: true,
      );

      await _tap(tester, 'Pay ₹3,650 via UPI');
      expect(h.links.opened, [upi]);
      expect(chooser, isFalse);
      debugDefaultTargetPlatformOverride = null;
    });
  });

  testWidgets('payee without a UPI ID: plain message, record cash instead', (
    tester,
  ) async {
    final h = await _pump(
      tester,
      location: SettloRoutes.settlePayTo('s2', 'm5'),
      spaces: settleSpaces(kabirUpiId: null),
    );
    expect(
      find.text(
        "Kabir hasn't added a UPI ID yet. Pay them however you usually do, "
        'then record it here.',
      ),
      findsOne,
    );
    expect(find.textContaining('via UPI'), findsNothing);

    await _tap(tester, 'Record a cash payment');
    expect(h.expenses.calls, isEmpty);
    await _tap(tester, 'Yes, I paid');
    expect(h.expenses.calls.single.expense.isSettlement, isTrue);
    expect(h.links.opened, isEmpty);
  });

  testWidgets('request on WhatsApp names your UPI ID and records nothing', (
    tester,
  ) async {
    final h = await _pump(
      tester,
      location: SettloRoutes.settleWith('s1', memberId: 'm3'),
    );
    await _tap(tester, 'Send request on WhatsApp');

    final uri = h.links.opened.single;
    expect((uri.host, uri.path), ('wa.me', '/919900000010'));
    expect(
      uri.queryParameters['text'],
      'Hi Priya, settling up Flat 402: please pay ₹2,100 to sana@okaxis on '
      'any UPI app. Sent from Settlo.',
    );
    expect(h.expenses.calls, isEmpty);
  });

  testWidgets('without your UPI ID the request side offers cash', (
    tester,
  ) async {
    await _pump(
      tester,
      location: SettloRoutes.settleWith('s1', memberId: 'm3'),
      spaces: settleSpaces(yourUpiId: null),
    );
    expect(
      find.text('Add your UPI ID in Profile to request through UPI.'),
      findsOne,
    );
    expect(find.text('Record payment'), findsOne);
    expect(find.text('Send request on WhatsApp'), findsNothing);
  });

  testWidgets('settled with them already', (tester) async {
    await _pump(tester, location: SettloRoutes.settlePayTo('s1', 'm3'));
    expect(find.text("You're settled up with them."), findsOne);
  });

  testWidgets('targets are at least 44pt and amounts are read in rupees', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();
    await _pump(tester, location: SettloRoutes.settlePayTo('s2', 'm5'));

    await expectLater(tester, meetsGuideline(iOSTapTargetGuideline));
    expect(
      find.bySemanticsLabel('three thousand six hundred fifty rupees'),
      findsOne,
    );
    semantics.dispose();
  });
}
