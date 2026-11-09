import 'dart:async';

import 'package:flutter/material.dart';
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

Future<void> _tap(WidgetTester tester, String text) async {
  await tester.tap(find.text(text));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('settle up: both payments, then everyone is at zero', (
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

    // Back on the list, which reloaded: only Priya's payment is left.
    expect(find.text('1 PAYMENT'), findsOne);
    expect(find.text('You pay Kabir'), findsNothing);

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

    expect(find.text("You're all settled up."), findsOne);
    expect([
      for (final s in h.spaces.spaces)
        for (final m in s.members) m.balance,
    ], everyElement(Paise.zero));
    expect(h.links.opened, hasLength(2));
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

    expect(
      find.textContaining('No UPI app on this phone opened it.'),
      findsOne,
    );
    expect(find.text('Did you pay Kabir ₹3,650?'), findsNothing);
    expect(h.expenses.calls, isEmpty);
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
