import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:settlo_core/settlo_core.dart';
import 'package:settlo_expenses/settlo_expenses.dart';
import 'package:settlo_test_support/golden.dart';

import 'support/fake_expenses.dart';
import 'support/fake_spaces.dart';

/// Flat 402: Sana (you, m1), Rahul (m2), Priya (m3).
final SpaceSummary _flat = spacesList.first;

/// Pushes Add expense at [location] over a stand-in screen, with [spaces]
/// and [expenses] behind it. Returns the router and the provider container.
Future<(GoRouter, ProviderContainer)> _pump(
  WidgetTester tester,
  FakeExpensesRepository expenses, {
  List<SpaceSummary>? spaces,
  String? location,
  GoldenDevice device = SettloGoldenDevices.canvas390,
}) async {
  await loadSettloFonts();
  tester.view
    ..physicalSize = device.size
    ..devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final container = ProviderContainer(
    overrides: [
      spacesRepositoryProvider.overrideWithValue(
        FakeSpacesRepository(spaces ?? [_flat]),
      ),
      expensesRepositoryProvider.overrideWithValue(expenses),
    ],
  );
  addTearDown(container.dispose);
  final router = GoRouter(
    initialLocation: SettloRoutes.home,
    routes: [
      for (final path in [SettloRoutes.home, SettloRoutes.spaces])
        GoRoute(path: path, builder: (_, state) => Text('at ${state.uri}')),
      ...expensesRoutes,
    ],
  );
  addTearDown(router.dispose);
  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: MaterialApp.router(
        theme: SettloTheme.dark(),
        routerConfig: router,
      ),
    ),
  );
  unawaited(router.push(location ?? SettloRoutes.addExpenseIn(_flat.id)));
  await tester.pumpAndSettle();
  return (router, container);
}

Finder get _amount => find.byType(TextField).at(0);
Finder get _description => find.byType(TextField).at(1);
Finder _input(SplitType? type, String memberId) =>
    find.byKey(ValueKey<(SplitType?, String)>((type, memberId)));

Future<void> _tap(WidgetTester tester, Finder finder) async {
  await tester.ensureVisible(finder);
  await tester.pumpAndSettle();
  await tester.tap(finder);
  await tester.pumpAndSettle();
}

Future<void> _type(WidgetTester tester, Finder field, String text) async {
  await tester.ensureVisible(field);
  await tester.enterText(field, text);
  await tester.pumpAndSettle();
}

/// Amount and description, the minimum to save.
Future<void> _fill(WidgetTester tester, String amount) async {
  await _type(tester, _amount, amount);
  await _type(tester, _description, 'Groceries');
}

/// A split type's segment, or the multiple payers toggle.
Finder _mode(String label) => label == 'Multiple payers'
    ? find.bySemanticsLabel(label)
    : find.text(label);

Future<void> _split(WidgetTester tester, String label) =>
    _tap(tester, find.text(label));

bool _saveEnabled(WidgetTester tester) =>
    tester.widget<FilledButton>(find.byType(FilledButton)).onPressed != null;

Future<void> _save(WidgetTester tester) =>
    _tap(tester, find.text('Save expense'));

/// What the last attempt split, member id to paise.
Map<String, int> _splits(FakeExpensesRepository r) => {
  for (final s in r.calls.last.expense.splits) s.memberId: s.amount.value,
};

/// Gold pixels in the sheet's page outside the Save button, and inside it.
Future<(int, int)> _gold(WidgetTester tester) async {
  var boundary = tester.renderObject(find.byType(AddExpenseSheet));
  while (!boundary.isRepaintBoundary) {
    boundary = boundary.parent!;
  }
  final origin = (boundary as RenderBox).localToGlobal(Offset.zero);
  final save = tester.getRect(find.byType(FilledButton)).shift(-origin);
  final (width, data) = (await tester.runAsync(() async {
    final image = await captureImage(
      tester.element(find.byType(AddExpenseSheet)),
    );
    return (image.width, (await image.toByteData())!);
  }))!;
  final gold = SettloColors.dark.action;
  int channel(double v) => (v * 255).round();
  var (outside, inside) = (0, 0);
  for (var i = 0; i < data.lengthInBytes; i += 4) {
    if ((data.getUint8(i) - channel(gold.r)).abs() <= 4 &&
        (data.getUint8(i + 1) - channel(gold.g)).abs() <= 4 &&
        (data.getUint8(i + 2) - channel(gold.b)).abs() <= 4) {
      final p = Offset((i ~/ 4 % width) + 0.5, (i ~/ 4 ~/ width) + 0.5);
      save.contains(p) ? inside++ : outside++;
    }
  }
  return (outside, inside);
}

void main() {
  testWidgets('opens on the space: you paid, split equally', (tester) async {
    await _pump(tester, FakeExpensesRepository());

    expect(find.text('New expense · Flat 402'), findsOne);
    expect(
      tester.getSemantics(find.bySemanticsLabel('You').first),
      isSemantics(isSelected: true, isButton: true),
    );
    expect(find.text('Odd paise go to whoever paid.'), findsOne);

    await _type(tester, _amount, '1800');
    expect(find.text('1,800'), findsOne);
    expect(find.text('₹600'), findsNWidgets(3));
    expect(_saveEnabled(tester), isFalse, reason: 'needs a description');

    await _type(tester, _description, 'Groceries · BigBasket');
    expect(_saveEnabled(tester), isTrue);
  });

  group('equal', () {
    testWidgets('odd paise go to the payer', (tester) async {
      final expenses = FakeExpensesRepository();
      final (router, container) = await _pump(tester, expenses);
      await _fill(tester, '100.01');
      await _tap(tester, find.bySemanticsLabel('Rahul'));
      await _tap(tester, find.text('Groceries').last);
      await _save(tester);

      final e = expenses.calls.single.expense;
      expect(e.spaceId, 's1');
      expect(e.description, 'Groceries');
      expect(e.category, 'groceries');
      expect(e.amount, const Paise(10001));
      expect(e.spentOn, isNull);
      expect(e.splitType, SplitType.equal);
      expect(e.payers, {'m2': const Paise(10001)});
      expect(_splits(expenses), {'m1': 3333, 'm2': 3335, 'm3': 3333});
      expect(container.read(ledgerRevisionProvider), 1);
      expect(router.state.uri.toString(), SettloRoutes.home, reason: 'closed');
    });

    testWidgets('only the people ticked share it', (tester) async {
      final expenses = FakeExpensesRepository();
      await _pump(tester, expenses);
      await _fill(tester, '100.01');
      await _tap(tester, find.text('Priya').last);
      expect(find.text('₹50.01'), findsOne);
      await _save(tester);
      expect(_splits(expenses), {'m1': 5001, 'm2': 5000});
    });

    testWidgets('nobody ticked cannot be saved', (tester) async {
      await _pump(tester, FakeExpensesRepository());
      await _fill(tester, '100');
      for (final name in ['You', 'Rahul', 'Priya']) {
        await _tap(tester, find.text(name).last);
      }
      expect(find.text('Pick at least one person.'), findsOne);
      expect(_saveEnabled(tester), isFalse);
    });
  });

  testWidgets('exact: live remainder, then saves the typed amounts', (
    tester,
  ) async {
    final expenses = FakeExpensesRepository();
    await _pump(tester, expenses);
    await _fill(tester, '1000');
    await _split(tester, 'Exact');
    await _type(tester, _input(SplitType.exact, 'm1'), '500');
    await _type(tester, _input(SplitType.exact, 'm2'), '400');
    expect(find.text('₹100 still to assign.'), findsOne);
    expect(_saveEnabled(tester), isFalse);
    await _type(tester, _input(SplitType.exact, 'm3'), '200');
    expect(find.text('₹100 more than the amount.'), findsOne);
    await _type(tester, _input(SplitType.exact, 'm3'), '99.99');
    expect(find.text('₹0.01 still to assign.'), findsOne);
    await _type(tester, _input(SplitType.exact, 'm3'), '100');

    await _save(tester);
    expect(expenses.calls.single.expense.splitType, SplitType.exact);
    expect(_splits(expenses), {'m1': 50000, 'm2': 40000, 'm3': 10000});
  });

  testWidgets('percent: must make 100%; a tied paisa goes to the payer', (
    tester,
  ) async {
    final expenses = FakeExpensesRepository();
    await _pump(tester, expenses);
    await _fill(tester, '1.01');
    await _tap(tester, find.bySemanticsLabel('Rahul'));
    await _split(tester, '%');
    await _type(tester, _input(SplitType.percent, 'm1'), '50');
    await _type(tester, _input(SplitType.percent, 'm2'), '33.5');
    expect(find.text('Adds up to 83.50%. It needs to make 100%.'), findsOne);
    expect(_saveEnabled(tester), isFalse);
    await _type(tester, _input(SplitType.percent, 'm2'), '50');

    await _save(tester);
    final splits = expenses.calls.single.expense.splits;
    expect(_splits(expenses), {'m1': 50, 'm2': 51});
    expect([for (final s in splits) s.percentBp], [5000, 5000]);
  });

  testWidgets('shares: in proportion; a tied paisa goes to the payer', (
    tester,
  ) async {
    final expenses = FakeExpensesRepository();
    await _pump(tester, expenses);
    await _fill(tester, '10.02');
    await _tap(tester, find.bySemanticsLabel('Priya'));
    await _split(tester, 'Shares');
    expect(find.text('Give at least one person a share.'), findsOne);
    for (final (id, n) in [('m1', '2'), ('m2', '1'), ('m3', '1')]) {
      await _type(tester, _input(SplitType.shares, id), n);
    }
    expect(find.text('₹5.01'), findsOne);

    await _save(tester);
    final splits = expenses.calls.single.expense.splits;
    expect(_splits(expenses), {'m1': 501, 'm2': 250, 'm3': 251});
    expect([for (final s in splits) s.shares], [2, 1, 1]);
  });

  testWidgets('multiple payers must add up to the amount', (tester) async {
    final expenses = FakeExpensesRepository();
    await _pump(tester, expenses);
    await _fill(tester, '1800');
    await _tap(tester, find.bySemanticsLabel('Multiple payers'));
    await _type(tester, _input(null, 'm2'), '1000');
    await _type(tester, _input(null, 'm3'), '500');
    expect(find.text('₹300 still to assign.'), findsOne);
    expect(_saveEnabled(tester), isFalse);
    await _type(tester, _input(null, 'm3'), '800.01');
    expect(find.text('₹0.01 more than the amount.'), findsOne);
    await _type(tester, _input(null, 'm3'), '800');

    await _save(tester);
    expect(expenses.calls.single.expense.payers, {
      'm2': const Paise(100000),
      'm3': const Paise(80000),
    });
  });

  group('saving', () {
    testWidgets('a retry after a failure reuses the idempotency key', (
      tester,
    ) async {
      final expenses = FakeExpensesRepository()
        ..failures.add(Exception('timed out'));
      final (router, container) = await _pump(tester, expenses);
      await _fill(tester, '420');
      await _save(tester);

      expect(
        find.text(
          "We couldn't save the expense. Check your connection and try "
          "again. It won't be recorded twice.",
        ),
        findsOne,
      );
      expect(container.read(ledgerRevisionProvider), 0);

      await _save(tester);
      expect(expenses.calls, hasLength(2));
      expect(expenses.calls.first.key, expenses.calls.last.key);
      final (first, last) = (
        expenses.calls.first.expense,
        expenses.calls.last.expense,
      );
      expect(last.amount, first.amount);
      expect(last.payers, first.payers);
      expect(last.splits, first.splits);
      expect(container.read(ledgerRevisionProvider), 1);
      expect(router.state.uri.toString(), SettloRoutes.home);
    });

    testWidgets('a new sheet gets a new key', (tester) async {
      final expenses = FakeExpensesRepository();
      final (router, _) = await _pump(tester, expenses);
      await _fill(tester, '420');
      await _save(tester);
      unawaited(router.push(SettloRoutes.addExpenseIn('s1')));
      await tester.pumpAndSettle();
      await _fill(tester, '420');
      await _save(tester);
      expect(expenses.calls.first.key, isNot(expenses.calls.last.key));
    });

    for (final (error, copy) in [
      (
        const IdempotencyConflict(),
        'This expense was already saved with the details you first entered. '
            'Close this to see it.',
      ),
      (
        const ExpenseRejected(),
        "This expense doesn't match the space any more. Someone may have "
            'left. Check who paid and who it is split with, then save again.',
      ),
    ]) {
      testWidgets('${error.runtimeType} is explained in plain words', (
        tester,
      ) async {
        final expenses = FakeExpensesRepository()..failures.add(error);
        await _pump(tester, expenses);
        await _fill(tester, '420');
        await _save(tester);
        expect(find.text(copy), findsOne);
        expect(find.text('New expense · Flat 402'), findsOne, reason: 'open');
      });
    }
  });

  testWidgets('Close goes back without saving', (tester) async {
    final expenses = FakeExpensesRepository();
    final (router, _) = await _pump(tester, expenses);
    await _tap(tester, find.bySemanticsLabel('Close'));
    expect(router.state.uri.toString(), SettloRoutes.home);
    expect(expenses.calls, isEmpty);
  });

  group('from Home', () {
    testWidgets('asks which space when there are several', (tester) async {
      await _pump(
        tester,
        FakeExpensesRepository(),
        spaces: spacesList,
        location: SettloRoutes.addExpense,
      );
      expect(find.text('WHICH SPACE?'), findsOne);
      await _tap(tester, find.text('Goa trip'));
      expect(find.text('New expense · Goa trip'), findsOne);
      // Five people: the first three are one tap, the rest via +.
      await _tap(tester, find.bySemanticsLabel('Multiple payers'));
      expect(_input(null, 'm8'), findsOne, reason: 'Isha can pay');
    });

    testWidgets('goes straight to your only space', (tester) async {
      await _pump(
        tester,
        FakeExpensesRepository(),
        location: SettloRoutes.addExpense,
      );
      expect(find.text('New expense · Flat 402'), findsOne);
    });

    testWidgets('without a space, offers to start one', (tester) async {
      final (router, _) = await _pump(
        tester,
        FakeExpensesRepository(),
        spaces: const [],
        location: SettloRoutes.addExpense,
      );
      await _tap(tester, find.text('Start a space'));
      expect(router.state.uri.toString(), SettloRoutes.spaces);
    });
  });

  // Gold means the one primary action (context pack); ruling on PR #71.
  testWidgets('nothing but Save is gold, in every selection state', (
    tester,
  ) async {
    await _pump(tester, FakeExpensesRepository());
    await _fill(tester, '1800');
    await _tap(tester, find.text('Groceries').first);
    for (final mode in ['Equally', 'Exact', '%', 'Shares', 'Multiple payers']) {
      await _tap(tester, _mode(mode));
      if (mode == 'Exact') {
        for (final id in ['m1', 'm2', 'm3']) {
          await _type(tester, _input(SplitType.exact, id), '600');
        }
      }
      FocusManager.instance.primaryFocus?.unfocus();
      await tester.pumpAndSettle();
      final (outside, inside) = await _gold(tester);
      expect(outside, 0, reason: '$mode: gold outside Save');
      // A disabled Save (nothing typed for % yet) is not gold either.
      expect(
        inside,
        _saveEnabled(tester) ? greaterThan(50) : 0,
        reason: '$mode: Save',
      );
    }
  });

  testWidgets('amounts are announced in rupees', (tester) async {
    await _pump(tester, FakeExpensesRepository());
    await _type(tester, _amount, '1800');
    expect(find.bySemanticsLabel(RegExp('^Amount in rupees')), findsOne);
    expect(
      find.bySemanticsLabel(RegExp('six hundred rupees')),
      findsNWidgets(3),
    );
    expect(find.bySemanticsLabel(RegExp('₹')), findsNothing);
  });

  group('every control is at least 44x44pt', () {
    for (final mode in ['Equally', 'Exact', '%', 'Shares', 'Multiple payers']) {
      testWidgets(mode, (tester) async {
        await _pump(tester, FakeExpensesRepository());
        await _fill(tester, '1800');
        await _tap(tester, _mode(mode));
        await expectLater(tester, meetsGuideline(iOSTapTargetGuideline));
        await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));
      });
    }
  });

  // Flutter reports any overflow to the test binding, which fails the test.
  group('fits 360x800 without overflow', () {
    for (final mode in ['Equally', 'Exact', '%', 'Shares']) {
      testWidgets(mode, (tester) async {
        await _pump(
          tester,
          FakeExpensesRepository(),
          spaces: [spacesList[1]],
          device: SettloGoldenDevices.compact360,
        );
        await _type(tester, _amount, '9,99,99,999.99');
        await _type(
          tester,
          _description,
          'Dinner, cab and tickets for the whole weekend',
        );
        await _tap(tester, find.bySemanticsLabel('Multiple payers'));
        await _tap(tester, _mode(mode));
        await tester.drag(
          find.byType(CustomScrollView),
          const Offset(0, -2000),
        );
        await tester.pumpAndSettle();
      });
    }
  });
}
