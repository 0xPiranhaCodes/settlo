import 'dart:async';
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:settlo_core/settlo_core.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Records GoTrue calls and throws [error] when set.
class _FakeGoTrue extends Fake implements GoTrueClient {
  Exception? error;
  final calls = <String>[];

  @override
  Future<void> signInWithOtp({
    String? email,
    String? phone,
    String? emailRedirectTo,
    bool? shouldCreateUser,
    Map<String, dynamic>? data,
    String? captchaToken,
    OtpChannel channel = OtpChannel.sms,
  }) async {
    calls.add('send $phone ${channel.name} create=${shouldCreateUser ?? true}');
    if (error case final e?) throw e;
  }

  @override
  Future<AuthResponse> verifyOTP({
    required OtpType type,
    String? email,
    String? phone,
    String? token,
    String? redirectTo,
    String? captchaToken,
    String? tokenHash,
  }) async {
    calls.add('verify $phone $token ${type.name}');
    if (error case final e?) throw e;
    return AuthResponse(
      user: const User(
        id: '00000000-0000-0000-0000-000000000001',
        appMetadata: {},
        userMetadata: {},
        aud: 'authenticated',
        createdAt: '2026-11-10T00:00:00Z',
      ),
    );
  }
}

void main() {
  late _FakeGoTrue goTrue;
  late PhoneAuth auth;
  setUp(() {
    goTrue = _FakeGoTrue();
    auth = SupabasePhoneAuth(goTrue);
  });

  test('sends an SMS code, signing up unknown numbers the same way', () async {
    await auth.sendCode('+919000000001');
    expect(goTrue.calls, ['send +919000000001 sms create=true']);
  });

  test('verifies an SMS code', () async {
    final userId = await auth.verifyCode(
      phone: '+919000000001',
      code: '123456',
    );
    expect(goTrue.calls, ['verify +919000000001 123456 sms']);
    expect(userId, '00000000-0000-0000-0000-000000000001');
  });

  group('maps failures', () {
    final cases = <(String, Exception, PhoneAuthFailure)>[
      (
        'wrong or expired code',
        const AuthApiException(
          'Token has expired or is invalid',
          statusCode: '403',
          code: 'otp_expired',
        ),
        PhoneAuthFailure.rejected,
      ),
      (
        'SMS provider refused',
        const AuthApiException(
          'Error sending confirmation OTP',
          statusCode: '500',
          code: 'sms_send_failed',
        ),
        PhoneAuthFailure.rejected,
      ),
      (
        'rate limit by status',
        const AuthApiException('Too many', statusCode: '429'),
        PhoneAuthFailure.rateLimited,
      ),
      (
        'rate limit by code',
        const AuthApiException(
          'For security purposes, you can only request this after 5 seconds',
          statusCode: '400',
          code: 'over_sms_send_rate_limit',
        ),
        PhoneAuthFailure.rateLimited,
      ),
      (
        'retryable fetch',
        AuthRetryableFetchException(message: 'gateway'),
        PhoneAuthFailure.network,
      ),
      (
        'no connection',
        const SocketException('offline'),
        PhoneAuthFailure.network,
      ),
      ('timeout', TimeoutException('slow'), PhoneAuthFailure.network),
    ];
    for (final (name, error, failure) in cases) {
      test(name, () async {
        goTrue.error = error;
        final expected = throwsA(
          isA<PhoneAuthException>().having(
            (e) => e.failure,
            'failure',
            failure,
          ),
        );
        await expectLater(auth.sendCode('+919000000001'), expected);
        await expectLater(
          auth.verifyCode(phone: '+919000000001', code: '123456'),
          expected,
        );
      });
    }
  });

  test("the provider wraps the client provider's auth", () {
    final client = SupabaseClient('http://localhost', 'anon');
    addTearDown(client.dispose);
    final container = ProviderContainer(
      overrides: [supabaseClientProvider.overrideWithValue(client)],
    );
    addTearDown(container.dispose);
    expect(container.read(phoneAuthProvider), isA<SupabasePhoneAuth>());
  });
}
