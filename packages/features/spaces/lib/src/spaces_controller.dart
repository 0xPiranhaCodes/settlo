import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:settlo_core/settlo_core.dart';

/// The signed-in user's spaces, loaded through [spacesRepositoryProvider].
final AsyncNotifierProvider<SpacesController, List<SpaceSummary>>
spacesProvider = AsyncNotifierProvider<SpacesController, List<SpaceSummary>>(
  SpacesController.new,
);

/// Loads the spaces and creates new ones. A created space reloads the
/// list, so it appears as the server recorded it, and bumps
/// [ledgerRevisionProvider] so Home reloads too.
class SpacesController extends AsyncNotifier<List<SpaceSummary>> {
  @override
  Future<List<SpaceSummary>> build() =>
      ref.watch(spacesRepositoryProvider).load();

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
}
