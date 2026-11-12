import 'package:flutter/widgets.dart';
import 'package:go_router/go_router.dart';
import 'package:settlo_core/settlo_core.dart';
import 'package:settlo_profile/src/screens.dart';

/// Profile, nested under the Home tab ([SettloRoutes.profile]) but shown
/// on [root], the app's root navigator, as a sheet over the shell (#196):
/// Home and the tab bar stay behind it, and a deep link opens it over Home.
GoRoute profileRoute(GlobalKey<NavigatorState> root) => GoRoute(
  path: 'profile',
  parentNavigatorKey: root,
  pageBuilder: (_, state) => SettloNavigatorSheetPage<void>(
    key: state.pageKey,
    child: const ProfileScreen(),
  ),
);
