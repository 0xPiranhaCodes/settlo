import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:settlo_core/settlo_core.dart';

/// The signed-in user's spaces, loaded through [spacesRepositoryProvider].
final AsyncNotifierProvider<SpacesController, List<SpaceSummary>>
spacesProvider = AsyncNotifierProvider<SpacesController, List<SpaceSummary>>(
  SpacesController.new,
);

/// Loads the spaces, creates new ones and adds people to them. A created
/// space reloads the list, so it appears as the server recorded it, and bumps
/// [ledgerRevisionProvider] so Home reloads too; a bump from another
/// feature, such as a new expense, reloads the spaces.
class SpacesController extends AsyncNotifier<List<SpaceSummary>> {
  @override
  Future<List<SpaceSummary>> build() {
    ref.watch(ledgerRevisionProvider);
    return ref.watch(spacesRepositoryProvider).load();
  }

  /// Creates a space and returns its id. Throws if the server refuses; a
  /// retry must pass the same [idempotencyKey].
  Future<String> create({
    required String name,
    required SpaceKind kind,
    required List<NewSpaceMember> members,
    required String idempotencyKey,
  }) async {
    final id = await ref
        .read(spacesRepositoryProvider)
        .create(
          name: name,
          kind: kind,
          members: members,
          idempotencyKey: idempotencyKey,
        );
    ref.read(ledgerRevisionProvider.notifier).bump();
    ref.invalidateSelf();
    await future;
    return id;
  }

  /// Adds [members] to space [spaceId] and reloads, as [create] does. A
  /// retry must pass the same [idempotencyKey].
  Future<void> addMembers(
    String spaceId,
    List<NewSpaceMember> members, {
    required String idempotencyKey,
  }) async {
    await ref
        .read(spacesRepositoryProvider)
        .addMembers(spaceId, members, idempotencyKey: idempotencyKey);
    ref.read(ledgerRevisionProvider.notifier).bump();
    ref.invalidateSelf();
    await future;
  }
}
