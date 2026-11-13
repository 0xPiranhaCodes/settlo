import 'package:flutter/widgets.dart';
import 'package:go_router/go_router.dart';
import 'package:settlo_core/settlo_core.dart';
import 'package:settlo_profile/src/screens.dart';

/// Profile at [path], shown on [root], the app's root navigator, as a sheet
/// over the shell (#196): top-level at [SettloRoutes.profileSheet], pushed
/// over whichever tab is open, and nested under Home at
/// [SettloRoutes.profile], so a deep link opens it over Home.
GoRoute profileRoute(GlobalKey<NavigatorState> root, String path) => GoRoute(
  path: path,
  parentNavigatorKey: root,
  pageBuilder: (_, state) => SettloNavigatorSheetPage<void>(
    key: state.pageKey,
    child: const ProfileScreen(),
  ),
);
