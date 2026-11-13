import 'package:flutter/widgets.dart';
import 'package:go_router/go_router.dart';
import 'package:settlo_core/settlo_core.dart';
import 'package:settlo_spaces/src/confirm_settlement_screen.dart';
import 'package:settlo_spaces/src/screens.dart';
import 'package:settlo_spaces/src/spaces_list.dart';

/// The Spaces tab, with a space's expenses and balances under it.
final GoRoute spacesTabRoute = GoRoute(
  path: SettloRoutes.spaces,
  builder: (_, _) => const SpacesListScreen(),
  routes: [
    GoRoute(
      path: ':spaceId',
      pageBuilder: (_, state) => _spacePage(
        state,
        SpaceExpensesScreen(spaceId: state.pathParameters['spaceId']!),
      ),
    ),
    GoRoute(
      path: ':spaceId/activity',
      pageBuilder: (_, state) => _spacePage(
        state,
        SpaceActivityScreen(spaceId: state.pathParameters['spaceId']!),
      ),
    ),
    // A sibling, not a child: Expenses and Balances are segments of one
    // destination, so Back from either returns to Spaces.
    GoRoute(
      path: ':spaceId/balances',
      pageBuilder: (_, state) => _spacePage(
        state,
        SpaceScreen(spaceId: state.pathParameters['spaceId']!),
      ),
    ),
  ],
);

/// Confirming a settle-up by path, a sheet over whatever opened it (such
/// as Activity), matched beside the tabs.
final List<RouteBase> spacesRoutes = [
  GoRoute(
    path: SettloRoutes.confirmSettlementPattern,
    pageBuilder: (context, state) => SettloSheetPage<void>(
      key: state.pageKey,
      child: ConfirmSettlementScreen(
        spaceId: state.pathParameters['spaceId']!,
        expenseId: state.pathParameters['expenseId']!,
      ),
    ),
  ),
];

/// A space's page. Explicit pages: go_router's default has no iOS swipe
/// back. All segments share its key, so switching updates it in place
/// instead of pushing.
Page<void> _spacePage(GoRouterState state, Widget child) => SettloPage<void>(
  key: ValueKey('space ${state.pathParameters['spaceId']}'),
  child: child,
);
