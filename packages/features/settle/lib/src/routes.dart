import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:settlo_core/settlo_core.dart';
import 'package:settlo_settle/src/screens.dart';

/// Settle up and its paying side: sheets over whatever opened them.
/// `?space=<id>` narrows to one space; `&member=<id>` picks the person.
final List<RouteBase> settleRoutes = [
  GoRoute(
    path: SettloRoutes.settle,
    pageBuilder: (context, state) => _sheet(
      context,
      state,
      SettleScreen(
        spaceId: state.uri.queryParameters['space'],
        memberId: state.uri.queryParameters['member'],
      ),
    ),
    routes: [
      GoRoute(
        path: 'pay',
        pageBuilder: (context, state) => _sheet(
          context,
          state,
          SettlePayScreen(
            spaceId: state.uri.queryParameters['space'],
            memberId: state.uri.queryParameters['member'],
          ),
        ),
      ),
    ],
  ),
];

Page<void> _sheet(BuildContext context, GoRouterState state, Widget child) =>
    SettloSheetPage<void>(key: state.pageKey, child: child);
