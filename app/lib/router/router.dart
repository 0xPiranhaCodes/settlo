import 'dart:async';

import 'package:app_links/app_links.dart';
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
    onException: (_, state, router) {
      final join = invitePathForUri(state.uri);
      router.go(
        join ?? (signedIn.value ? SettloRoutes.home : SettloRoutes.welcome),
      );
    },
    routes: _routes(flatChrome: ref.read(flatChromeProvider)),
  );
  final links = ref.read(deepLinkSourceProvider);
  void openInvite(Uri uri) {
    final path = invitePathForUri(uri);
    if (path != null) router.go(path);
  }

  unawaited(
    links.initial.then((uri) {
      if (uri != null) openInvite(uri);
    }),
  );
  final linkSubscription = links.changes.listen(openInvite);
  ref
    ..onDispose(linkSubscription.cancel)
    ..onDispose(router.dispose);
  return router;
});

/// Turns the custom-scheme shape delivered by iOS/Android into the route
/// shared with the future HTTPS link. Other URIs are not invite links.
String? invitePathForUri(Uri uri) {
  if (uri.scheme != 'settlo' || uri.host != 'join') return null;
  final segments = uri.pathSegments.where((part) => part.isNotEmpty).toList();
  return segments.length == 1 ? SettloRoutes.join(segments.single) : null;
}

/// Cold- and warm-start links delivered by the host platforms.
abstract interface class DeepLinkSource {
  /// The link that launched the process, if any.
  Future<Uri?> get initial;

  /// Links delivered while the process is already alive.
  Stream<Uri> get changes;
}

final class _PlatformDeepLinks implements DeepLinkSource {
  new(this._links);

  final AppLinks _links;

  @override
  Future<Uri?> get initial => _links.getInitialLink();

  @override
  Stream<Uri> get changes => _links.uriLinkStream;
}

/// The platform link source; tests override it for cold and warm delivery.
final deepLinkSourceProvider = Provider<DeepLinkSource>(
  (_) => _PlatformDeepLinks(AppLinks()),
);

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
