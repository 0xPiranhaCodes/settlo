import 'package:go_router/go_router.dart';
import 'package:settlo_balances/src/screens.dart';
import 'package:settlo_core/settlo_core.dart';

/// The Home tab. The app nests other features' Home sub-routes in [routes].
GoRoute homeTabRoute({List<RouteBase> routes = const []}) => GoRoute(
  path: SettloRoutes.home,
  builder: (_, _) => const HomeScreen(),
  routes: routes,
);
