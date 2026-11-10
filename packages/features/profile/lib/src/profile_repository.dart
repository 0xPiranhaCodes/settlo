import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:settlo_core/settlo_core.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// The signed-in user's editable profile.
@immutable
final class ProfileData {
  /// A profile row.
  const new({required this.name, required this.phone, required this.upiId});

  /// Display name.
  final String name;

  /// Verified E.164 phone number.
  final String phone;

  /// VPA used to prefill settle-ups, or null when none is saved.
  final String? upiId;
}

/// Profile reads and writes. Widgets never call PostgREST directly.
abstract interface class ProfileRepository {
  /// Loads the signed-in user's profile.
  Future<ProfileData> load();

  /// Saves [name] and [upiId] through `update_profile`.
  Future<void> update({required String name, required String? upiId});

  /// Ends the current session.
  Future<void> signOut();

  /// Deletes the account through `delete_account`, then drops the session.
  /// Retries when no answer comes back, and counts a session the server no
  /// longer accepts as deleted.
  Future<void> deleteAccount();
}

/// A validation error safe to show directly to the user.
final class ProfileInputException implements Exception {
  /// A safe validation error.
  const new(this.message);

  /// Plain, customer-facing copy.
  final String message;
}

/// [ProfileRepository] backed by the interim online Supabase client.
final class SupabaseProfileRepository implements ProfileRepository {
  /// Reads and writes [userId] through [client].
  const new(
    this.client, {
    required this.userId,
    this.deleteWait = const Duration(seconds: 15),
    this.deleteRetryIn = const Duration(seconds: 1),
  });

  /// How long [deleteAccount] waits for each answer.
  final Duration deleteWait;

  /// The pause before [deleteAccount] asks again.
  final Duration deleteRetryIn;

  /// Supabase client.
  final SupabaseClient client;

  /// Signed-in user id.
  final String userId;

  @override
  Future<ProfileData> load() async {
    final row = await client
        .from('profiles')
        .select('name, phone, upi_id')
        .eq('id', userId)
        .single();
    return ProfileData(
      name: (row['name'] as String?) ?? '',
      phone: row['phone'] as String,
      upiId: row['upi_id'] as String?,
    );
  }

  @override
  Future<void> update({required String name, required String? upiId}) async {
    try {
      await client.rpc<void>(
        'update_profile',
        params: {'p_name': name, 'p_upi_id': upiId},
      );
    } on PostgrestException catch (error) {
      if (error.code == '22023') {
        throw ProfileInputException(
          error.hint == 'invalid_vpa'
              ? upiValidationMessage
              : nameValidationMessage,
        );
      }
      rethrow;
    }
  }

  @override
  Future<void> signOut() => client.auth.signOut();

  @override
  Future<void> deleteAccount() async {
    // A lost answer says nothing about whether the server deleted the
    // account. `delete_account` is idempotent, so ask again; three tries,
    // then the caller offers the retry.
    for (var attempt = 1; ; attempt++) {
      try {
        await client.rpc<void>('delete_account').timeout(deleteWait);
        break;
      } on PostgrestException catch (error) {
        // The server no longer accepts this session (an invalid or expired
        // token, or no user in it): there is nothing left to delete with it.
        final code = error.code ?? '';
        if (!code.startsWith('PGRST30') && code != '42501') rethrow;
        break;
      } on AuthRetryableFetchException {
        if (attempt == 3) rethrow;
      } on AuthException {
        // The session could not be refreshed: the user is already gone.
        break;
      } on Object {
        // No answer: a timeout or a dropped connection.
        if (attempt == 3) rethrow;
      }
      await Future<void>.delayed(deleteRetryIn);
    }
    // This drops the local session first, then tells a server that has no
    // such user any more; that second half failing means nothing.
    try {
      await client.auth.signOut();
    } on AuthException {
      // Already signed out here.
    }
  }
}

/// Profile data for the current session. Tests replace this provider.
final profileRepositoryProvider = Provider<ProfileRepository>((ref) {
  final userId = ref.watch(
    sessionProvider.select((session) => session?.user.id),
  );
  if (userId == null) throw StateError('Profile needs a signed-in user');
  return SupabaseProfileRepository(
    ref.watch(supabaseClientProvider),
    userId: userId,
  );
});

/// Server-matching name validation copy.
const nameValidationMessage = 'Enter your name (up to 100 characters).';

/// Server-matching UPI validation copy. Raw `22023` details never escape.
const upiValidationMessage =
    'Enter a UPI ID like name@bank using letters, numbers, dots, dashes or '
    'underscores.';

final _vpa = RegExp(r'^[A-Za-z0-9._-]{1,255}@[A-Za-z]{2,64}$');

/// Validates a name exactly as `update_profile` does.
String? validateProfileName(String? value) {
  final name = value?.trim() ?? '';
  return name.isEmpty || name.runes.length > 100 ? nameValidationMessage : null;
}

/// Validates a VPA exactly as `public.is_vpa`; blank clears the saved VPA.
String? validateUpiId(String? value) {
  final upi = value?.trim() ?? '';
  return upi.isEmpty || _vpa.hasMatch(upi) ? null : upiValidationMessage;
}
