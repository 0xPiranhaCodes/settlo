import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:settlo_core/settlo_core.dart';
import 'package:settlo_profile/src/profile_repository.dart';

/// The current profile, loaded through [profileRepositoryProvider].
final profileProvider = AsyncNotifierProvider<ProfileController, ProfileData>(
  ProfileController.new,
);

/// Loads and updates the signed-in user's profile.
class ProfileController extends AsyncNotifier<ProfileData> {
  /// Whether the sign-out or delete-account row is already asking or
  /// working, so a double tap starts one.
  bool leaving = false;

  @override
  Future<ProfileData> build() => ref.watch(profileRepositoryProvider).load();

  /// Saves the profile, reloads server-normalised values, and refreshes ledgers
  /// that show the user's name.
  Future<void> save({required String name, required String? upiId}) async {
    final trimmedUpi = upiId?.trim();
    await ref
        .read(profileRepositoryProvider)
        .update(
          name: name.trim(),
          upiId: trimmedUpi == null || trimmedUpi.isEmpty ? null : trimmedUpi,
        );
    ref.read(ledgerRevisionProvider.notifier).bump();
    ref.invalidateSelf();
    await future;
  }

  /// Signs out. The app's session listener performs navigation.
  Future<void> signOut() => ref.read(profileRepositoryProvider).signOut();

  /// Deletes the account and signs out; the session listener navigates,
  /// and the offline mirror and queue are wiped as on any sign-out.
  ///
  /// Syncing stops first, so no queued write is sent once the deletion
  /// starts; it resumes, queue intact, if the account could not be deleted.
  Future<void> deleteAccount() async {
    final unsent = ref.read(unsentChangesProvider);
    await unsent?.stop();
    try {
      await ref.read(profileRepositoryProvider).deleteAccount();
    } on Object {
      unsent?.resume();
      rethrow;
    }
  }
}
