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
import 'package:settlo_platform/settlo_platform.dart';
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
    routes: _routes(flatChrome: ref.read(flatChromeProvider)),
  );
  ref.onDispose(router.dispose);
  return router;
});

final _rootKey = GlobalKey<NavigatorState>();

// Each feature exports its routes (ADR 0002); the app only composes them.
// Full-screen routes sit beside the shell, so they cover the tab bar.
List<RouteBase> _routes({required bool flatChrome}) => [
  ...authRoutes,
  ...expensesRoutes,
  ...settleRoutes,
  ...loansRoutes,
  ...spacesRoutes,
  StatefulShellRoute.indexedStack(
    builder: (_, _, shell) => SettloShell(
      flatChrome: flatChrome,
      currentIndex: shell.currentIndex,
      onTabSelected: (i) =>
          shell.goBranch(i, initialLocation: i == shell.currentIndex),
      child: shell,
    ),
    branches: [
      for (final route in [
        homeTabRoute(routes: [profileRoute]),
        spacesTabRoute,
        loansTabRoute,
        activityTabRoute,
      ])
        StatefulShellBranch(routes: [route]),
    ],
  ),
];
