import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:settlo_core/settlo_core.dart';
import 'package:settlo_expenses/src/screens.dart';

/// Add expense: a sheet over whatever opened it, so the space stays in
/// view behind it (canvas note n13). `?space=<id>` picks the space.
final List<RouteBase> expensesRoutes = [
  GoRoute(
    path: SettloRoutes.addExpense,
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
      child: AddExpenseScreen(spaceId: state.uri.queryParameters['space']),
    ),
  ),
];
