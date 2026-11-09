import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:settlo/shell.dart';
import 'package:settlo_balances/settlo_balances.dart';
import 'package:settlo_core/settlo_core.dart';
import 'package:settlo_profile/settlo_profile.dart';
import 'package:settlo_spaces/settlo_spaces.dart';
import 'package:settlo_test_support/golden.dart';

import 'support/fake_home.dart';
import 'support/fake_profile.dart';
import 'support/fake_session.dart';
import 'support/fake_space_ledger.dart';
import 'support/fake_spaces.dart';

/// A keyboard's height on a phone this size.
const _keyboard = 336.0;

/// An iPhone's home indicator inset.
const _homeIndicator = 34.0;

/// Pumps the app's shell at [location], as the router composes it: the
/// tab bar floats over every tab, so a sheet left inside the shell would
/// lie under it (#81).
Future<void> _pump(
  WidgetTester tester,
  GoldenDevice device,
  String location,
) async {
  await loadSettloFonts();
  tester.view
    ..physicalSize = device.size
    ..devicePixelRatio = 1
    ..viewPadding = const FakeViewPadding(bottom: _homeIndicator)
    ..padding = const FakeViewPadding(bottom: _homeIndicator);
  addTearDown(tester.view.reset);
  final router = GoRouter(
    initialLocation: location,
    routes: [
      StatefulShellRoute.indexedStack(
        builder: (_, _, shell) => SettloShell(
          currentIndex: shell.currentIndex,
          onTabSelected: shell.goBranch,
          child: shell,
        ),
        branches: [
          StatefulShellBranch(
            routes: [
              homeTabRoute(routes: [profileRoute]),
            ],
          ),
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
        homeRepositoryProvider.overrideWithValue(FakeHomeRepository(homeMain)),
        profileRepositoryProvider.overrideWithValue(FakeProfileRepository()),
        themeModeRepositoryProvider.overrideWithValue(
          FakeThemeModeRepository(),
        ),
        spacesRepositoryProvider.overrideWithValue(
          FakeSpacesRepository(spacesList),
        ),
        spaceLedgerRepositoryProvider.overrideWithValue(
          FakeSpaceLedgerRepository(),
        ),
      ],
      child: MaterialApp.router(
        theme: SettloTheme.dark(),
        routerConfig: router,
      ),
    ),
  );
  await tester.pumpAndSettle();
}

/// Raises the keyboard: it covers the home indicator, so the view's
/// padding drops to zero while its view padding stays.
Future<void> _raiseKeyboard(WidgetTester tester) async {
  tester.view
    ..viewInsets = const FakeViewPadding(bottom: _keyboard)
    ..padding = FakeViewPadding.zero;
  await tester.pumpAndSettle();
}

Future<void> _tap(WidgetTester tester, Finder finder) async {
  await tester.ensureVisible(finder);
  await tester.pumpAndSettle();
  await tester.tap(finder);
  await tester.pumpAndSettle();
}

/// Each sheet: where it opens, how, and its primary action.
final _sheets = <({String name, String location, Finder open, Finder action})>[
  (
    name: 'edit profile',
    location: SettloRoutes.profile,
    open: find.text('Name and UPI ID'),
    action: find.text('Save'),
  ),
  (
    name: 'appearance',
    location: SettloRoutes.profile,
    open: find.text('Appearance'),
    // The lowest option.
    action: find.text('Use system setting'),
  ),
  (
    name: 'create space',
    location: SettloRoutes.spaces,
    open: find.byTooltip('New space'),
    action: find.text('Create space'),
  ),
  (
    name: 'edit expense',
    location: SettloRoutes.space('s1'),
    open: find.text('Groceries · BigBasket'),
    action: find.text('Save changes'),
  ),
];

void main() {
  for (final device in SettloGoldenDevices.all) {
    for (final sheet in _sheets) {
      for (final keyboard in [false, true]) {
        final label =
            '${sheet.name}, ${device.name}, '
            '${keyboard ? 'keyboard up' : 'no keyboard'}';

        testWidgets('the primary action is above the tab bar: $label', (
          tester,
        ) async {
          await _pump(tester, device, sheet.location);
          await _tap(tester, sheet.open);
          if (keyboard) await _raiseKeyboard(tester);

          await tester.ensureVisible(sheet.action);
          await tester.pumpAndSettle();
          expect(sheet.action.hitTestable(), findsOne);
          final action = tester.getRect(sheet.action);
          final bottom = device.size.height - (keyboard ? _keyboard : 0);
          expect(action.bottom, lessThanOrEqualTo(bottom));
        });
      }
    }
  }

  testWidgets('edit profile saves at 390x844 with the shell present', (
    tester,
  ) async {
    await _pump(tester, SettloGoldenDevices.canvas390, SettloRoutes.profile);
    await _tap(tester, find.text('Name and UPI ID'));
    await tester.enterText(find.byKey(const ValueKey('profile-name')), 'Asha');
    await _raiseKeyboard(tester);

    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();

    expect(find.text('Save'), findsNothing);
    expect(find.text('Asha'), findsOne);
  });
}
