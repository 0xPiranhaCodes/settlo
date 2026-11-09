import 'package:go_router/go_router.dart';
import 'package:settlo_core/settlo_core.dart';
import 'package:settlo_settle/src/screens.dart';

/// Settle up and its paying side, full screen over the tabs.
final List<RouteBase> settleRoutes = [
  GoRoute(
    path: SettloRoutes.settle,
    builder: (_, _) => const SettleScreen(),
    routes: [GoRoute(path: 'pay', builder: (_, _) => const SettlePayScreen())],
  ),
];
