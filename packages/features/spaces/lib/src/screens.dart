import 'package:flutter/widgets.dart';
import 'package:settlo_core/settlo_core.dart';

/// Placeholder for the SpacesList artboard.
class SpacesListScreen extends StatelessWidget {
  /// The SpacesList screen.
  const new({super.key});

  @override
  Widget build(BuildContext context) =>
      const SPlaceholderScreen(title: 'Spaces', artboard: 'SpacesList');
}

/// Placeholder for the SpaceExpenses artboard.
class SpaceExpensesScreen extends StatelessWidget {
  /// The SpaceExpenses screen for [spaceId].
  const new({required this.spaceId, super.key});

  /// The space shown.
  final String spaceId;

  @override
  Widget build(BuildContext context) =>
      const SPlaceholderScreen(title: 'Expenses', artboard: 'SpaceExpenses');
}

/// Placeholder for the Space artboard.
class SpaceScreen extends StatelessWidget {
  /// The Space screen for [spaceId].
  const new({required this.spaceId, super.key});

  /// The space shown.
  final String spaceId;

  @override
  Widget build(BuildContext context) =>
      const SPlaceholderScreen(title: 'Balances', artboard: 'Space');
}
