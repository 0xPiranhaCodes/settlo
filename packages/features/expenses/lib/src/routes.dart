import 'package:go_router/go_router.dart';
import 'package:settlo_core/settlo_core.dart';
import 'package:settlo_expenses/src/screens.dart';

/// Add expense, full screen over the tabs.
final List<RouteBase> expensesRoutes = [
  GoRoute(
    path: SettloRoutes.addExpense,
    builder: (_, _) => const AddExpenseScreen(),
  ),
];
