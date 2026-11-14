import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:settlo/shell.dart';
import 'package:settlo_activity/settlo_activity.dart';
import 'package:settlo_auth/settlo_auth.dart';
import 'package:settlo_balances/settlo_balances.dart';
import 'package:settlo_core/settlo_core.dart';
import 'package:settlo_core/supabase/reminders.dart';
import 'package:settlo_expenses/settlo_expenses.dart';
import 'package:settlo_loans/settlo_loans.dart';
import 'package:settlo_profile/settlo_profile.dart';
import 'package:settlo_settle/settlo_settle.dart';
import 'package:settlo_spaces/settlo_spaces.dart';
import 'package:settlo_test_support/golden.dart';

import 'support/fake_activity.dart';
import 'support/fake_home.dart';
import 'support/fake_loans.dart';
import 'support/fake_phone_auth.dart';
import 'support/fake_profile.dart';
import 'support/fake_reminders.dart';
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
Future<void> pumpTaskGolden(
  WidgetTester tester,
  GoldenDevice device,
  String location, {
  ThemeData? theme,
}) async {
  await loadSettloFonts();
  final previousShadows = debugDisableShadows;
  debugDisableShadows = false;
  try {
    tester.view
      ..physicalSize = device.size
      ..devicePixelRatio = 1
      ..viewPadding = const FakeViewPadding(bottom: _homeIndicator)
      ..padding = const FakeViewPadding(bottom: _homeIndicator);
    addTearDown(tester.view.reset);
    tester.platformDispatcher.textScaleFactorTestValue = device.textScale;
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    final root = GlobalKey<NavigatorState>();
    final router = GoRouter(
      navigatorKey: root,
      initialLocation: location,
      routes: [
        ...authRoutes,
        ...loansRoutes,
        ...expensesRoutes,
        ...settleRoutes,
        StatefulShellRoute.indexedStack(
          builder: (_, _, shell) => SettloShell(
            currentIndex: shell.currentIndex,
            onTabSelected: shell.goBranch,
            child: shell,
          ),
          branches: [
            StatefulShellBranch(
              routes: [
                homeTabRoute(routes: [profileRoute(root, 'profile')]),
              ],
            ),
            StatefulShellBranch(routes: [spacesTabRouteFor(root)]),
            StatefulShellBranch(routes: [loansTabRouteFor(root)]),
            StatefulShellBranch(routes: [activityTabRoute]),
          ],
        ),
      ],
    );
    addTearDown(router.dispose);
    await tester.pumpWidget(
      RepaintBoundary(
        key: settloGoldenSurfaceKey,
        child: ProviderScope(
          overrides: [
            phoneAuthProvider.overrideWithValue(FakePhoneAuth()),
            reminderRepositoryProvider.overrideWithValue(FakeReminders()),
            loansRepositoryProvider.overrideWithValue(
              FakeLoansRepository(loansList()),
            ),
            indiaTodayProvider.overrideWithValue(DateTime(2026, 11, 9)),
            activityRepositoryProvider.overrideWithValue(
              FakeActivityRepository(),
            ),
            activityNowProvider.overrideWithValue(DateTime(2026, 11, 9, 18)),
            unsentChangesProvider.overrideWithValue((
              count: () async => 2,
              drain: () async {},
              stop: () async {},
              resume: () {},
            )),
            sessionProvider.overrideWith(
              () => FakeSessionNotifier(fakeSession),
            ),
            homeRepositoryProvider.overrideWithValue(
              FakeHomeRepository(homeMain),
            ),
            profileRepositoryProvider.overrideWithValue(
              FakeProfileRepository(),
            ),
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
            debugShowCheckedModeBanner: false,
            theme: theme ?? SettloTheme.dark(),
            routerConfig: router,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  } finally {
    debugDisableShadows = previousShadows;
  }
}

/// Raises the keyboard: it covers the home indicator, so the view's
/// padding drops to zero while its view padding stays.
Future<void> _raiseKeyboard(WidgetTester tester) async {
  tester.view
    ..viewInsets = const FakeViewPadding(bottom: _keyboard)
    ..padding = FakeViewPadding.zero;
  await tester.pumpAndSettle();
}

Future<void> tapTaskControl(WidgetTester tester, Finder finder) async {
  final previousShadows = debugDisableShadows;
  debugDisableShadows = false;
  try {
    if (finder.evaluate().isEmpty) {
      await tester.scrollUntilVisible(
        finder,
        200,
        scrollable: find
            .byWidgetPredicate(
              (widget) =>
                  widget is Scrollable &&
                  widget.axisDirection == AxisDirection.down,
            )
            // The top route's list: with Profile's sheet over Home, Home's
            // list is still in the tree.
            .hitTestable()
            .first,
      );
    }
    // A tab root's header scrolls away, so revealing one of its actions
    // would scroll it off (#197); at rest it is always on screen.
    final inHeader = find.ancestor(
      of: finder,
      matching: find.byType(SettloNavigationHeader),
    );
    if (inHeader.evaluate().isEmpty) {
      await tester.ensureVisible(finder);
      await tester.pumpAndSettle();
    }
    await tester.tap(finder);
    await tester.pumpAndSettle();
  } finally {
    debugDisableShadows = previousShadows;
  }
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
  // A missed tap captures the screen underneath instead of the sheet.
  setUpAll(() => WidgetController.hitTestWarningShouldBeFatal = true);
  tearDownAll(() => WidgetController.hitTestWarningShouldBeFatal = false);

  for (final device in [
    ...SettloGoldenDevices.accessible,
    const GoldenDevice(name: 'se375x667', size: Size(375, 667)),
    const GoldenDevice(
      name: 'se375x667_text200',
      size: Size(375, 667),
      textScale: 2,
    ),
  ]) {
    for (final (themeName, theme) in [
      ('dark', SettloTheme.dark()),
      ('light', SettloTheme.light()),
    ]) {
      for (final (name, location, open, action)
          in <(String, String, Finder, Finder?)>[
            for (final sheet in _sheets)
              (sheet.name, sheet.location, sheet.open, sheet.action),
            ('export', SettloRoutes.profile, find.text('Export'), null),
            (
              'sign out unsent',
              SettloRoutes.profile,
              find.text('Sign out'),
              null,
            ),
            (
              'country picker',
              SettloRoutes.phone,
              find.byKey(const ValueKey('country-chip')),
              null,
            ),
            (
              'question edit',
              SettloRoutes.activity,
              find.text('Rahul edited Wifi · Airtel'),
              null,
            ),
            (
              'record repayment',
              SettloRoutes.loan('l1'),
              find.text('Record repayment'),
              null,
            ),
            (
              'loan dispute',
              SettloRoutes.loan('l1'),
              find.text('Not received'),
              null,
            ),
            (
              'confirmation dispute',
              SettloRoutes.confirmRepayment('r3'),
              find.text("Didn't receive this"),
              null,
            ),
            (
              'delete account',
              SettloRoutes.profile,
              find.text('Delete account'),
              null,
            ),
          ]) {
        testWidgets('$name ${device.name} $themeName panel golden', (
          tester,
        ) async {
          await pumpTaskGolden(tester, device, location, theme: theme);
          await tapTaskControl(tester, open);
          if (action != null) expect(action, findsOne, reason: 'it opened');
          expectSettloTapTargets(tester);
          expectNoMidWordBreaks(tester);
          expectSettloTypeMinimum(tester);
          await expectLater(
            find.byKey(settloGoldenSurfaceKey),
            matchesGoldenFile(
              'goldens/sheet_${name.replaceAll(' ', '_')}_${device.name}_$themeName.png',
            ),
          );
        });
      }
    }
  }

  for (final device in SettloGoldenDevices.all) {
    for (final sheet in _sheets) {
      for (final keyboard in [false, true]) {
        final label =
            '${sheet.name}, ${device.name}, '
            '${keyboard ? 'keyboard up' : 'no keyboard'}';

        testWidgets('the primary action is above the tab bar: $label', (
          tester,
        ) async {
          await pumpTaskGolden(tester, device, sheet.location);
          await tapTaskControl(tester, sheet.open);
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
    await pumpTaskGolden(
      tester,
      SettloGoldenDevices.canvas390,
      SettloRoutes.profile,
    );
    await tapTaskControl(tester, find.text('Name and UPI ID'));
    await tester.enterText(find.byKey(const ValueKey('profile-name')), 'Asha');
    await _raiseKeyboard(tester);

    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();

    expect(find.text('Save'), findsNothing);
    // The header scrolled out of the lazy list when the row was brought up.
    // Profile's list is the last: its sheet is over Home's (#196).
    final scroll = tester.state<ScrollableState>(
      find
          .byWidgetPredicate(
            (widget) =>
                widget is Scrollable &&
                widget.axisDirection == AxisDirection.down,
          )
          .last,
    );
    scroll.position.jumpTo(0);
    await tester.pumpAndSettle();
    expect(find.text('Asha'), findsOne);
  });
}
