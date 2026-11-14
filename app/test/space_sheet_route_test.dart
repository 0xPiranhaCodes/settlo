import 'dart:async';

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:settlo_core/settlo_core.dart';
import 'package:settlo_expenses/settlo_expenses.dart';
import 'package:settlo_settle/settlo_settle.dart';
import 'package:settlo_spaces/settlo_spaces.dart';

import 'support/fake_activity.dart';
import 'support/fake_expenses.dart';
import 'support/fake_space_ledger.dart';
import 'support/fake_spaces.dart';

void main() {
  for (final platform in [TargetPlatform.iOS, TargetPlatform.android]) {
    testWidgets('space segments and actions stay above tabs on $platform', (
      tester,
    ) async {
      final root = GlobalKey<NavigatorState>();
      final router = GoRouter(
        navigatorKey: root,
        initialLocation: SettloRoutes.spaces,
        routes: [
          ...expensesRoutes,
          ...settleRoutes,
          ShellRoute(
            builder: (_, _, child) => Scaffold(
              body: child,
              bottomNavigationBar: const SizedBox(
                height: 60,
                child: Text('Tab bar'),
              ),
            ),
            routes: [spacesTabRouteFor(root)],
          ),
        ],
      );
      addTearDown(router.dispose);
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            activityRepositoryProvider.overrideWithValue(
              FakeActivityRepository(),
            ),
            spacesRepositoryProvider.overrideWithValue(
              FakeSpacesRepository(spacesList),
            ),
            spaceLedgerRepositoryProvider.overrideWithValue(
              FakeSpaceLedgerRepository(),
            ),
            expensesRepositoryProvider.overrideWithValue(
              FakeExpensesRepository(),
            ),
          ],
          child: MaterialApp.router(
            theme: SettloTheme.light().copyWith(platform: platform),
            routerConfig: router,
          ),
        ),
      );
      await tester.pumpAndSettle();
      unawaited(router.push(SettloRoutes.space('s1')));
      await tester.pumpAndSettle();
      final route = ModalRoute.of(
        tester.element(find.byType(SpaceExpensesScreen)),
      )!;
      expect(route.navigator, root.currentState);
      expect(route is CupertinoSheetRoute, platform == TargetPlatform.iOS);
      expect(find.text('Tab bar').hitTestable(), findsNothing);
      await tester.tap(find.text('Balances'));
      await tester.pumpAndSettle();
      expect(find.byType(SpaceScreen), findsOneWidget);
      expect(
        ModalRoute.of(tester.element(find.byType(SpaceScreen))),
        same(route),
      );
      final segments = tester.getCenter(find.text('Balances'));
      await tester.tap(find.text('Activity'));
      await tester.pumpAndSettle();
      expect(find.byType(SpaceActivityScreen), findsOneWidget);
      expect(
        ModalRoute.of(tester.element(find.byType(SpaceActivityScreen))),
        same(route),
      );
      expect(tester.getCenter(find.text('Balances')), segments);
      expect(find.text('Tab bar').hitTestable(), findsNothing);
      expect(find.byType(SSheetScaffold), findsOneWidget);
      expect(
        find.descendant(
          of: find.byType(SSheetScaffold),
          matching: find.byType(
            CupertinoSliverRefreshControl,
            skipOffstage: false,
          ),
          skipOffstage: false,
        ),
        platform == TargetPlatform.iOS ? findsOneWidget : findsNothing,
      );
      expect(
        find.descendant(
          of: find.byType(SSheetScaffold),
          matching: find.byType(RefreshIndicator),
        ),
        platform == TargetPlatform.android ? findsOneWidget : findsNothing,
      );
      for (final action in ['Add expense', 'Settle up']) {
        await tester.tap(find.text(action));
        await tester.pumpAndSettle();
        expect(
          action == 'Add expense'
              ? find.byType(AddExpenseScreen)
              : find.byType(SettleScreen),
          findsOneWidget,
        );
        router.pop();
        await tester.pumpAndSettle();
        expect(find.byType(SpaceActivityScreen), findsOneWidget);
      }
      await tester.tap(find.bySemanticsLabel('Close'));
      await tester.pumpAndSettle();
      expect(find.text('Tab bar').hitTestable(), findsOneWidget);
      expect(router.state.uri.path, SettloRoutes.spaces);
      expect(tester.takeException(), isNull);
    });
  }
}
