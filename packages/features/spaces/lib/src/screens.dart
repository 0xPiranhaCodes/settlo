import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:settlo_core/settlo_core.dart';
import 'package:settlo_spaces/src/space_empty.dart';
import 'package:settlo_spaces/src/spaces_controller.dart';

/// A space's expenses (SpaceExpenses artboard); Space · empty until
/// anything is recorded.
class SpaceExpensesScreen extends ConsumerWidget {
  /// The SpaceExpenses screen for [spaceId].
  const new({required this.spaceId, super.key});

  /// The space shown.
  final String spaceId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final space = ref
        .watch(spacesProvider)
        .value
        ?.where((s) => s.id == spaceId)
        .firstOrNull;
    return switch (space) {
      null => const Scaffold(),
      SpaceSummary(hasExpenses: false) => SpaceEmptyView(space),
      _ => const SPlaceholderScreen(
        title: 'Expenses',
        artboard: 'SpaceExpenses',
      ),
    };
  }
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
