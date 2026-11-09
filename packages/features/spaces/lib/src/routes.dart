import 'package:go_router/go_router.dart';
import 'package:settlo_core/settlo_core.dart';
import 'package:settlo_spaces/src/screens.dart';
import 'package:settlo_spaces/src/spaces_list.dart';

/// The Spaces tab, with a space's expenses and balances under it.
final GoRoute spacesTabRoute = GoRoute(
  path: SettloRoutes.spaces,
  builder: (_, _) => const SpacesListScreen(),
  routes: [
    GoRoute(
      path: ':spaceId',
      builder: (_, state) =>
          SpaceExpensesScreen(spaceId: state.pathParameters['spaceId']!),
      routes: [
        GoRoute(
          path: 'balances',
          builder: (_, state) =>
              SpaceScreen(spaceId: state.pathParameters['spaceId']!),
        ),
      ],
    ),
  ],
);
