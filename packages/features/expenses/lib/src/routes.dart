import 'package:go_router/go_router.dart';
import 'package:settlo_core/settlo_core.dart';
import 'package:settlo_expenses/src/screens.dart';

/// Add expense: a sheet over whatever opened it, so the space stays in
/// view behind it (canvas note n13). `?space=<id>` picks the space.
final List<RouteBase> expensesRoutes = [
  GoRoute(
    path: SettloRoutes.addExpense,
    pageBuilder: (context, state) => SettloPage<void>(
      key: state.pageKey,
      child: AddExpenseScreen(spaceId: state.uri.queryParameters['space']),
    ),
  ),
];
