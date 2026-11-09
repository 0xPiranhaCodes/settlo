import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:settlo/router/redirect.dart';
import 'package:settlo/shell.dart';
import 'package:settlo_activity/settlo_activity.dart';
import 'package:settlo_auth/settlo_auth.dart';
import 'package:settlo_balances/settlo_balances.dart';
import 'package:settlo_core/settlo_core.dart';
import 'package:settlo_expenses/settlo_expenses.dart';
import 'package:settlo_loans/settlo_loans.dart';
import 'package:settlo_profile/settlo_profile.dart';
import 'package:settlo_settle/settlo_settle.dart';
import 'package:settlo_spaces/settlo_spaces.dart';

/// The app's router: one route per canvas artboard, with the four tabs in a
/// shell and the auth guard re-run whenever the session changes.
///
/// Artboards that are a state of another screen rather than a destination
/// get no route: HomeEmpty, HomeFound and HomeLight are Home; SpaceEmpty is
/// Space; LiveActivity is an OS surface owned by `settlo_platform`.
final routerProvider = Provider<GoRouter>((ref) {
  final signedIn = ValueNotifier(ref.read(sessionProvider) != null);
  ref
    ..listen(sessionProvider, (_, session) => signedIn.value = session != null)
    ..onDispose(signedIn.dispose);
  final router = GoRouter(
    navigatorKey: _rootKey,
    initialLocation: SettloRoutes.home,
    refreshListenable: signedIn,
    redirect: (_, state) =>
        authRedirect(signedIn: signedIn.value, location: state.matchedLocation),
    routes: _routes,
  );
  ref.onDispose(router.dispose);
  return router;
});

final _rootKey = GlobalKey<NavigatorState>();

GoRoute _route(String path, Widget Function(GoRouterState) build) => GoRoute(
  path: path,
  parentNavigatorKey: _rootKey,
  builder: (_, state) => build(state),
);

final _routes = <RouteBase>[
  _route(SettloRoutes.splash, (_) => const SplashScreen()),
  _route(SettloRoutes.welcome, (_) => const WelcomeScreen()),
  _route(SettloRoutes.phone, (_) => const PhoneScreen()),
  _route(SettloRoutes.otp, (_) => const OtpScreen()),
  _route(
    SettloRoutes.joinPattern,
    (s) => JoinScreen(token: s.pathParameters['token']!),
  ),
  _route(SettloRoutes.addExpense, (_) => const AddExpenseScreen()),
  _route(SettloRoutes.settle, (_) => const SettleScreen()),
  _route(SettloRoutes.settlePay, (_) => const SettlePayScreen()),
  _route(SettloRoutes.newLoan, (_) => const NewLoanScreen()),
  _route(
    SettloRoutes.confirmRepaymentPattern,
    (s) =>
        ConfirmRepaymentScreen(repaymentId: s.pathParameters['repaymentId']!),
  ),
  StatefulShellRoute.indexedStack(
    builder: (_, _, shell) => SettloShell(
      currentIndex: shell.currentIndex,
      onTabSelected: (i) =>
          shell.goBranch(i, initialLocation: i == shell.currentIndex),
      child: shell,
    ),
    branches: [
      _branch(SettloRoutes.home, const HomeScreen(), [
        GoRoute(path: 'profile', builder: (_, _) => const ProfileScreen()),
      ]),
      _branch(SettloRoutes.spaces, const SpacesListScreen(), [
        GoRoute(
          path: ':spaceId',
          builder: (_, s) =>
              SpaceExpensesScreen(spaceId: s.pathParameters['spaceId']!),
          routes: [
            GoRoute(
              path: 'balances',
              builder: (_, s) =>
                  SpaceScreen(spaceId: s.pathParameters['spaceId']!),
            ),
          ],
        ),
      ]),
      _branch(SettloRoutes.loans, const LoanScreen()),
      _branch(SettloRoutes.activity, const ActivityScreen()),
    ],
  ),
];

StatefulShellBranch _branch(
  String path,
  Widget screen, [
  List<RouteBase> routes = const [],
]) => StatefulShellBranch(
  routes: [GoRoute(path: path, builder: (_, _) => screen, routes: routes)],
);
