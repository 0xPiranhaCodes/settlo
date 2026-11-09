import 'package:flutter/material.dart';
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
      builder: (_, state) =>
          SpaceExpensesScreen(spaceId: state.pathParameters['spaceId']!),
      routes: [
        GoRoute(
          path: 'balances',
          builder: (_, state) =>
              SpaceScreen(spaceId: state.pathParameters['spaceId']!),
        ),
      ],
    ),
  ],
);

/// Confirming a settle-up by path, a sheet over whatever opened it (such
/// as Activity), matched beside the tabs.
final List<RouteBase> spacesRoutes = [
  GoRoute(
    path: SettloRoutes.confirmSettlementPattern,
    pageBuilder: (context, state) => CustomTransitionPage<void>(
      key: state.pageKey,
      opaque: false,
      barrierDismissible: true,
      barrierColor: SettloColors.of(context).background.withValues(alpha: 0.6),
      transitionsBuilder: (_, animation, _, child) => SlideTransition(
        position: Tween(begin: const Offset(0, 1), end: Offset.zero).animate(
          CurvedAnimation(parent: animation, curve: Curves.easeOutCubic),
        ),
        child: child,
      ),
      child: ConfirmSettlementScreen(
        spaceId: state.pathParameters['spaceId']!,
        expenseId: state.pathParameters['expenseId']!,
      ),
    ),
  ),
];
