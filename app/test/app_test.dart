import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:settlo/main.dart' as app;
import 'package:settlo/router/router.dart';
import 'package:settlo_activity/settlo_activity.dart';
import 'package:settlo_auth/settlo_auth.dart';
import 'package:settlo_balances/settlo_balances.dart';
import 'package:settlo_core/settlo_core.dart';
import 'package:settlo_expenses/settlo_expenses.dart';
import 'package:settlo_loans/settlo_loans.dart';
import 'package:settlo_profile/settlo_profile.dart';
import 'package:settlo_settle/settlo_settle.dart';
import 'package:settlo_spaces/settlo_spaces.dart';
import 'package:settlo_test_support/golden.dart';

import 'support/fake_activity.dart';
import 'support/fake_session.dart';

GoRouter _router(WidgetTester tester) =>
    ProviderScope.containerOf(tester.element(find.byType(app.SettloApp)))
        .read(routerProvider);

FakeSessionNotifier _session(WidgetTester tester) =>
    ProviderScope.containerOf(tester.element(find.byType(app.SettloApp)))
            .read(sessionProvider.notifier)
        as FakeSessionNotifier;

Future<void> _go(WidgetTester tester, String location) async {
  _router(tester).go(location);
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('boots signed out to Welcome, without the tab bar', (
    tester,
  ) async {
    await tester.pumpWidget(fakeSessionApp(null));
    await tester.pumpAndSettle();

    expect(_router(tester).state.uri.path, SettloRoutes.welcome);
    expect(find.byType(WelcomeScreen), findsOneWidget);
    expect(find.byType(SGlassTabBar), findsNothing);
  });

  testWidgets('boots signed in to Home, with the tab bar', (tester) async {
    await tester.pumpWidget(fakeSessionApp(fakeSession));
    await tester.pumpAndSettle();

    expect(_router(tester).state.uri.path, SettloRoutes.home);
    expect(find.byType(HomeScreen), findsOneWidget);
    expect(find.byType(SGlassTabBar), findsOneWidget);
  });

  testWidgets('signing in and out re-runs the guard', (tester) async {
    await tester.pumpWidget(fakeSessionApp(null));
    await tester.pumpAndSettle();
    await _go(tester, SettloRoutes.otp);

    _session(tester).signIn();
    await tester.pumpAndSettle();
    expect(_router(tester).state.uri.path, SettloRoutes.home);

    await _go(tester, SettloRoutes.space('s1'));
    _session(tester).signOut();
    await tester.pumpAndSettle();
    expect(_router(tester).state.uri.path, SettloRoutes.welcome);
  });

  testWidgets('the bell counts what is new until Activity is opened, on '
      'every open (#109)', (tester) async {
    // Last open on 3 Nov at 22:00: two entries of other people's since.
    final activity = FakeActivityRepository(seenAt: DateTime(2026, 11, 3, 22));
    await tester.pumpWidget(fakeSessionApp(fakeSession, activity: activity));
    await tester.pumpAndSettle();
    expect(find.byTooltip('Notifications, 2 new'), findsOneWidget);

    await tester.tap(find.byTooltip('Notifications, 2 new'));
    await tester.pumpAndSettle();
    expect(find.byType(ActivityScreen), findsOneWidget);
    // Opening Activity marked what was new seen; it has no bell (#197).
    expect(find.byTooltip(RegExp('^Notifications')), findsNothing);
    expect(activity.seenAt, activityFeed.first.at);

    await tester.tap(find.text('Home'));
    await tester.pumpAndSettle();
    expect(find.byTooltip('Notifications'), findsOneWidget);

    // Something lands while Activity is a hidden tab: it waits for the
    // next open, though the tab was never rebuilt.
    activity.entries.insert(
      0,
      ActivityEntry(
        id: 7,
        at: DateTime(2026, 11, 9, 12),
        kind: ActivityKind.expense,
        action: ActivityAction.created,
        byYou: false,
        actor: 'Rahul',
        spaceId: 's1',
        spaceName: 'Flat 402',
        description: 'Milk',
        amount: const Paise.rupees(60),
      ),
    );
    final container = ProviderScope.containerOf(
      tester.element(find.byType(HomeScreen)),
    );
    container.read(ledgerRevisionProvider.notifier).bump();
    await tester.pumpAndSettle();
    expect(find.byTooltip('Notifications, 1 new'), findsOneWidget);
    expect(activity.seenAt, activityFeed.first.at);

    await tester.tap(find.text('Activity'));
    await tester.pumpAndSettle();
    expect(activity.seenAt, DateTime(2026, 11, 9, 12));
    await tester.tap(find.text('Home'));
    await tester.pumpAndSettle();
    expect(find.byTooltip('Notifications'), findsOneWidget);
  });

  testWidgets('tabs switch branches and keep each branch stack', (
    tester,
  ) async {
    await tester.pumpWidget(fakeSessionApp(fakeSession));
    await tester.pumpAndSettle();

    await tester.tap(
      find.descendant(
        of: find.byType(SGlassTabBar),
        matching: find.text('Spaces'),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.byType(SpacesListScreen), findsOneWidget);

    await _go(tester, SettloRoutes.space('s1'));
    expect(find.text('Loans').hitTestable(), findsNothing);
    await tester.tap(find.bySemanticsLabel('Close'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Loans'));
    await tester.pumpAndSettle();
    expect(find.byType(LoanScreen), findsOneWidget);

    await tester.tap(
      find.descendant(
        of: find.byType(SGlassTabBar),
        matching: find.text('Spaces'),
      ),
    );
    await tester.pumpAndSettle();
    expect(_router(tester).state.uri.path, SettloRoutes.spaces);

    // Tapping the selected tab returns to its root.
    await tester.tap(
      find.descendant(
        of: find.byType(SGlassTabBar),
        matching: find.text('Spaces'),
      ),
    );
    await tester.pumpAndSettle();
    expect(_router(tester).state.uri.path, SettloRoutes.spaces);

    await tester.tap(find.text('Activity'));
    await tester.pumpAndSettle();
    expect(find.byType(ActivityScreen), findsOneWidget);
    await tester.tap(find.text('Home'));
    await tester.pumpAndSettle();
    expect(find.byType(HomeScreen), findsOneWidget);
  });

  group('every route builds at 360x800 without overflow', () {
    // Overflow errors fail the test; none is consumed (docs/release.md).
    Future<void> boot(WidgetTester tester, {required bool signedIn}) async {
      await loadSettloFonts();
      tester.view
        ..physicalSize = SettloGoldenDevices.compact360.size
        ..devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(fakeSessionApp(signedIn ? fakeSession : null));
      await tester.pumpAndSettle();
    }

    final signedOut = <String, Type>{
      SettloRoutes.welcome: WelcomeScreen,
      SettloRoutes.phone: PhoneScreen,
      SettloRoutes.join('t1'): JoinScreen,
    };
    final signedIn = <String, Type>{
      SettloRoutes.home: HomeScreen,
      SettloRoutes.profile: ProfileScreen,
      SettloRoutes.spaces: SpacesListScreen,
      SettloRoutes.space('s1'): SpaceExpensesScreen,
      SettloRoutes.spaceBalances('s1'): SpaceScreen,
      SettloRoutes.loans: LoanScreen,
      SettloRoutes.loan('l1'): LoanDetailScreen,
      SettloRoutes.newLoan: NewLoanSheet,
      SettloRoutes.confirmRepayment('r1'): ConfirmRepaymentScreen,
      SettloRoutes.activity: ActivityScreen,
      SettloRoutes.addExpense: AddExpenseScreen,
      SettloRoutes.settle: SettleScreen,
      SettloRoutes.settlePay: SettlePayScreen,
    };

    for (final (isSignedIn, routes) in [(false, signedOut), (true, signedIn)]) {
      for (final MapEntry(key: path, value: screen) in routes.entries) {
        testWidgets(path, (tester) async {
          await boot(tester, signedIn: isSignedIn);
          await _go(tester, path);
          expect(_router(tester).state.uri.path, path);
          expect(find.byType(screen), findsOneWidget);
        });
      }
    }

    // OTP's own layout at 360 is in auth_layout_test.dart, with a code sent.
    testWidgets('OTP without a sent code goes back to Phone', (tester) async {
      await boot(tester, signedIn: false);
      await _go(tester, SettloRoutes.otp);
      expect(_router(tester).state.uri.path, SettloRoutes.phone);
      expect(find.byType(PhoneScreen), findsOneWidget);
    });

    testWidgets('Splash is reachable only on the way in', (tester) async {
      await boot(tester, signedIn: false);
      await _go(tester, SettloRoutes.splash);
      expect(_router(tester).state.uri.path, SettloRoutes.welcome);
      expect(find.byType(SplashScreen), findsNothing);
    });
  });

  test('main refuses to start without Supabase settings', () {
    expect(app.main, throwsStateError);
  });
}
