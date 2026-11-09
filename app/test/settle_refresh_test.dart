import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:settlo/shell.dart';
import 'package:settlo_core/settlo_core.dart';
import 'package:settlo_settle/settlo_settle.dart';
import 'package:settlo_spaces/settlo_spaces.dart';
import 'package:settlo_test_support/golden.dart';

import 'support/fake_session.dart';
import 'support/fake_settle.dart';
import 'support/fake_space_ledger.dart';
import 'support/fake_spaces.dart';

/// Loads as slowly as a real network, so reloads overlap the sheet
/// closing.
final class _SlowSpaces extends FakeSpacesRepository {
  new(super.spaces);

  @override
  Future<List<SpaceSummary>> load() =>
      Future.delayed(const Duration(milliseconds: 300), super.load);
}

/// The #65 gate's space: you owe ₹18.33, simplified to ₹11.68 to Charu
/// and ₹6.65 to Asha.
const _flat = SpaceSummary(
  id: 's9',
  name: 'Flat 65',
  kind: SpaceKind.flat,
  hasExpenses: true,
  members: [
    SpaceMember(
      id: 'b',
      name: 'Bela',
      phone: '+919000000002',
      isYou: true,
      balance: Paise(-1833),
    ),
    SpaceMember(
      id: 'c',
      name: 'Charu',
      phone: '+919000000003',
      balance: Paise(1168),
      upiId: 'charu@upi',
    ),
    SpaceMember(
      id: 'a',
      name: 'Asha',
      phone: '+919000000001',
      balance: Paise(665),
      upiId: 'asha@upi',
    ),
  ],
);

/// Lets the slow loads finish.
Future<void> _settle(WidgetTester tester) async {
  await tester.pump(const Duration(seconds: 1));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('confirmed settle-ups refresh the open Space › Balances', (
    tester,
  ) async {
    await loadSettloFonts();
    tester.view
      ..physicalSize = SettloGoldenDevices.canvas390.size
      ..devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final spaces = _SlowSpaces([_flat]);
    // As in the app: settle sheets on the root navigator, the space in a
    // shell branch beneath them.
    final router = GoRouter(
      initialLocation: SettloRoutes.spaceBalances(_flat.id),
      routes: [
        ...settleRoutes,
        StatefulShellRoute.indexedStack(
          builder: (_, _, shell) => SettloShell(
            currentIndex: shell.currentIndex,
            onTabSelected: shell.goBranch,
            child: shell,
          ),
          branches: [
            StatefulShellBranch(routes: [spacesTabRoute]),
          ],
        ),
      ],
    );
    addTearDown(router.dispose);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          sessionProvider.overrideWith(() => FakeSessionNotifier(fakeSession)),
          spacesRepositoryProvider.overrideWithValue(spaces),
          spaceLedgerRepositoryProvider.overrideWithValue(
            FakeSpaceLedgerRepository(),
          ),
          expensesRepositoryProvider.overrideWithValue(
            SettlingExpensesRepository(spaces),
          ),
          openUpiProvider.overrideWithValue((_) async => true),
        ],
        child: MaterialApp.router(
          theme: SettloTheme.dark(),
          routerConfig: router,
        ),
      ),
    );
    await _settle(tester);
    expect(find.text('2 PAYMENTS'), findsOne);

    for (final (amount, left) in [('₹11.68', '1 PAYMENT'), ('₹6.65', null)]) {
      await tester.tap(find.widgetWithText(TextButton, 'Pay').first);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Pay $amount via UPI'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Yes, I paid'));
      await _settle(tester);

      // Back on the space, with no pull to refresh.
      expect(find.text('Yes, I paid'), findsNothing);
      if (left != null) expect(find.text(left), findsOne);
    }

    expect(find.text('Everyone is settled up.'), findsOne);
    expect(find.widgetWithText(TextButton, 'Pay'), findsNothing);

    // The hero, drawn on the Expenses tab only, agrees.
    await tester.tap(find.text('Expenses'));
    await tester.pumpAndSettle();
    expect(find.text('ALL SETTLED'), findsOne);
  });
}
