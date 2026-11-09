import 'package:go_router/go_router.dart';
import 'package:settlo_activity/src/screens.dart';
import 'package:settlo_core/settlo_core.dart';

/// The Activity tab.
final GoRoute activityTabRoute = GoRoute(
  path: SettloRoutes.activity,
  builder: (_, _) => const ActivityScreen(),
);
