import 'dart:async';

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:settlo_core/settlo_core.dart';
import 'package:settlo_expenses/settlo_expenses.dart';
import 'package:settlo_loans/settlo_loans.dart';
import 'package:settlo_settle/settlo_settle.dart';
import 'package:settlo_spaces/settlo_spaces.dart';
import 'package:settlo_test_support/golden.dart';

import 'support/fake_expenses.dart';
import 'support/fake_loans.dart';
import 'support/fake_space_ledger.dart';
import 'support/fake_spaces.dart';

/// Pushes the production route at [location] over a stand-in Home.
Future<GoRouter> _push(
  WidgetTester tester,
  String location,
  TargetPlatform platform,
) async {
  await loadSettloFonts();
  tester.view
    ..physicalSize = SettloGoldenDevices.canvas390.size
    ..devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final router = GoRouter(
    initialLocation: SettloRoutes.home,
    routes: [
      for (final path in [
        SettloRoutes.home,
        SettloRoutes.spaces,
        SettloRoutes.loans,
      ])
        GoRoute(path: path, builder: (_, state) => Text('at ${state.uri}')),
      ...expensesRoutes,
      ...settleRoutes,
      ...loansRoutes,
      ...spacesRoutes,
    ],
  );
  addTearDown(router.dispose);
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        spacesRepositoryProvider.overrideWithValue(
          FakeSpacesRepository(spacesList),
        ),
        spaceLedgerRepositoryProvider.overrideWithValue(
          FakeSpaceLedgerRepository(),
        ),
        expensesRepositoryProvider.overrideWithValue(FakeExpensesRepository()),
        loansRepositoryProvider.overrideWithValue(
          FakeLoansRepository(loansList()),
        ),
      ],
      child: MaterialApp.router(
        theme: SettloTheme.dark().copyWith(platform: platform),
        routerConfig: router,
      ),
    ),
  );
  unawaited(router.push(location));
  await tester.pumpAndSettle();
  return router;
}

void main() {
  final tasks = [
    ('Add expense', SettloRoutes.addExpenseIn('s1'), AddExpenseScreen),
    ('Settle up', SettloRoutes.settle, SettleScreen),
    ('New loan', SettloRoutes.newLoan, NewLoanSheet),
    (
      'Confirm settlement',
      SettloRoutes.confirmSettlement('s1', 'none'),
      ConfirmSettlementScreen,
    ),
  ];
  for (final platform in [TargetPlatform.iOS, TargetPlatform.android]) {
    final ios = platform == TargetPlatform.iOS;
    for (final (name, location, screen) in tasks) {
      testWidgets('$name is ${ios ? 'a native sheet' : 'a page'} on '
          '$platform', (tester) async {
        await _push(tester, location, platform);

        final route = ModalRoute.of(tester.element(find.byType(screen)));
        expect(route, isA<PageRoute<void>>());
        expect(route is CupertinoSheetRoute, ios, reason: location);
        if (ios) {
          // The route leaves the gap above the sheet; no canvas 54 on top.
          expect(tester.getTopLeft(find.byType(screen)).dy, greaterThan(0));
          expect(find.text('at ${SettloRoutes.home}'), findsOneWidget);
        }
      });
    }
  }

  testWidgets('on iOS, Add expense drags down from its title to dismiss', (
    tester,
  ) async {
    final router = await _push(
      tester,
      SettloRoutes.addExpenseIn('s1'),
      TargetPlatform.iOS,
    );
    expect(find.byType(AddExpenseScreen), findsOneWidget);

    await tester.flingFrom(
      tester.getCenter(find.text('New expense · Flat 402')),
      const Offset(0, 500),
      1500,
    );
    await tester.pumpAndSettle();

    expect(find.byType(AddExpenseScreen), findsNothing);
    expect(router.state.uri.toString(), SettloRoutes.home);
  });

  testWidgets('on Android, Add expense keeps its own drag to close', (
    tester,
  ) async {
    final router = await _push(
      tester,
      SettloRoutes.addExpenseIn('s1'),
      TargetPlatform.android,
    );

    await tester.flingFrom(
      tester.getCenter(find.text('New expense · Flat 402')),
      const Offset(0, 300),
      1500,
    );
    await tester.pumpAndSettle();

    expect(find.byType(AddExpenseScreen), findsNothing);
    expect(router.state.uri.toString(), SettloRoutes.home);
  });
}
