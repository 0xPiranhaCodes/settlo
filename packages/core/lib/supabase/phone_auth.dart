import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:settlo_core/supabase/providers.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Why a phone sign-in call failed, in terms the sign-in screens can word.
enum PhoneAuthFailure {
  /// The server refused the request: a number it cannot text, or a code
  /// that is wrong or expired.
  rejected,

  /// Too many requests for this number or device in a short time.
  rateLimited,

  /// The server could not be reached.
  network,
}

/// A failed [PhoneAuth] call.
final class PhoneAuthException implements Exception {
  /// A failure of kind [failure].
  const new(this.failure);

  /// What went wrong.
  final PhoneAuthFailure failure;

  @override
  String toString() => 'PhoneAuthException(${failure.name})';
}

/// Phone OTP sign-in. Features use this rather than the Supabase client, so
/// they never see Supabase types (ADR 0007) and tests can fake it.
abstract interface class PhoneAuth {
  /// Texts a one-time code to [phone], in E.164 (`+919876543210`). Throws
  /// [PhoneAuthException].
  Future<void> sendCode(String phone);

  /// Signs in with [code] sent to [phone] and returns the verified user id.
  /// [sessionProvider] follows asynchronously. Throws [PhoneAuthException].
  Future<String?> verifyCode({required String phone, required String code});
}

/// [PhoneAuth] through Supabase Auth.
///
/// Sign-in and sign-up are the same call (`shouldCreateUser` stays on), so
/// the response never tells whether the number already has an account.
final class SupabasePhoneAuth implements PhoneAuth {
  /// Signs in through the Supabase client's GoTrue `auth` client.
  const new(this._auth);

  final GoTrueClient _auth;

  @override
  Future<void> sendCode(String phone) =>
      _guard(() => _auth.signInWithOtp(phone: phone));

  @override
  Future<String?> verifyCode({
    required String phone,
    required String code,
  }) async {
    final response = await _guard(
      () => _auth.verifyOTP(phone: phone, token: code, type: OtpType.sms),
    );
    return response.user?.id ?? _auth.currentSession?.user.id;
  }

  static Future<T> _guard<T>(Future<T> Function() call) async {
    try {
      return await call();
    } on AuthRetryableFetchException {
      throw const PhoneAuthException(PhoneAuthFailure.network);
    } on AuthException catch (e) {
      final limited =
          e.statusCode == '429' || (e.code?.startsWith('over_') ?? false);
      throw PhoneAuthException(
        limited ? PhoneAuthFailure.rateLimited : PhoneAuthFailure.rejected,
      );
    } on Exception {
      // Socket, HTTP client and timeout errors.
      throw const PhoneAuthException(PhoneAuthFailure.network);
    }
  }
}

/// Phone OTP sign-in through [supabaseClientProvider]; tests override this.
final phoneAuthProvider = Provider<PhoneAuth>(
  (ref) => SupabasePhoneAuth(ref.watch(supabaseClientProvider).auth),
);
