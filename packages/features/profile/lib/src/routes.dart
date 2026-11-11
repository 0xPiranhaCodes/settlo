import 'package:go_router/go_router.dart';
import 'package:settlo_core/settlo_core.dart';
import 'package:settlo_profile/src/screens.dart';

/// Profile, nested under the Home tab ([SettloRoutes.profile]).
final GoRoute profileRoute = GoRoute(
  path: 'profile',
  // An explicit page: go_router's default here has no iOS swipe back.
  pageBuilder: (_, state) =>
      SettloPage<void>(key: state.pageKey, child: const ProfileScreen()),
);
