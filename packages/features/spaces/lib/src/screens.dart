import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:settlo_core/settlo_core.dart';
import 'package:settlo_spaces/src/space_detail.dart';
import 'package:settlo_spaces/src/space_empty.dart';
import 'package:settlo_spaces/src/spaces_controller.dart';

/// Space [spaceId] from the loaded list, or null until it loads.
SpaceSummary? _space(WidgetRef ref, String spaceId) =>
    ref.watch(spacesProvider).value?.where((s) => s.id == spaceId).firstOrNull;

/// A space's expenses (SpaceExpenses artboard); Space · empty until
/// anything is recorded.
class SpaceExpensesScreen extends ConsumerWidget {
  /// The SpaceExpenses screen for [spaceId].
  const new({required this.spaceId, super.key});

  /// The space shown.
  final String spaceId;

  @override
  Widget build(BuildContext context, WidgetRef ref) =>
      switch (_space(ref, spaceId)) {
        null => const Scaffold(),
        final s when !s.hasExpenses => SpaceEmptyView(s),
        final s => SpaceDetailView(s, tab: SpaceTab.expenses),
      };
}

/// A space's balances (Space artboard).
class SpaceScreen extends ConsumerWidget {
  /// The Space screen for [spaceId].
  const new({required this.spaceId, super.key});

  /// The space shown.
  final String spaceId;

  @override
  Widget build(BuildContext context, WidgetRef ref) =>
      switch (_space(ref, spaceId)) {
        null => const Scaffold(),
        final s => SpaceDetailView(s, tab: SpaceTab.balances),
      };
}
