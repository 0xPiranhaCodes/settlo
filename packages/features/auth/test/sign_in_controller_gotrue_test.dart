import 'dart:async';
import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:settlo_auth/settlo_auth.dart';
import 'package:settlo_core/settlo_core.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

final class _Client extends Fake implements SupabaseClient {
  new(this.auth);

  @override
  final GoTrueClient auth;
}

final class _Invites extends Fake implements InvitesRepository {
  InviteFailure? failure;
  Completer<void>? hold;
  int calls = 0;

  @override
  Future<void> redeem(String token, {required String idempotencyKey}) async {
    calls++;
    final completer = hold;
    if (completer != null) await completer.future;
    final redeemFailure = failure;
    if (redeemFailure != null) throw InviteException(redeemFailure);
  }
}

String _jwt(String subject, int version) {
  String encode(Object value) =>
      base64Url.encode(utf8.encode(jsonEncode(value))).replaceAll('=', '');
  return '${encode({'alg': 'HS256', 'typ': 'JWT'})}.'
      '${encode({'sub': subject, 'exp': 4102444800, 'version': version})}.'
      'signature';
}

Map<String, Object?> _sessionJson(String userId, int version) => {
  'access_token': _jwt(userId, version),
  'token_type': 'bearer',
  'expires_in': 3600,
  'refresh_token': 'refresh-$userId-$version',
  'user': {
    'id': userId,
    'aud': 'authenticated',
    'app_metadata': <String, Object?>{},
    'user_metadata': <String, Object?>{},
    'created_at': '2026-11-10T00:00:00Z',
    'phone': '919000000001',
  },
};

void main() {
  const userId = '00000000-0000-0000-0000-000000000001';
  late GoTrueClient goTrue;
  late _Invites invites;
  late ProviderContainer container;
  late int sessionVersion;

  setUp(() {
    sessionVersion = 0;
    goTrue = GoTrueClient(
      url: 'http://settlo.test/auth/v1',
      headers: const {'apikey': 'test-key'},
      autoRefreshToken: false,
      flowType: AuthFlowType.implicit,
      httpClient: MockClient((request) async {
        final body =
            request.url.path.endsWith('/verify') ||
                request.url.path.endsWith('/token')
            ? _sessionJson(userId, sessionVersion++)
            : <String, Object?>{};
        return http.Response(
          jsonEncode(body),
          200,
          headers: const {'content-type': 'application/json'},
        );
      }),
    );
    invites = _Invites();
    container =
        ProviderContainer(
            overrides: [
              supabaseClientProvider.overrideWithValue(_Client(goTrue)),
              invitesRepositoryProvider.overrideWithValue(invites),
            ],
          )
          ..listen(signInProvider, (_, _) {})
          ..listen(sessionProvider, (_, _) {})
          ..listen(inviteSignInNoticeProvider, (_, _) {});
  });

  tearDown(() => container.dispose());

  Future<void> start() async {
    container
        .read(pendingInviteTokenProvider.notifier)
        .remember('t' * 64, idempotencyKey: 'stable-key');
    final controller = container.read(signInProvider.notifier)
      ..updateNumber('9000000001');
    expect(await controller.sendCode(), isTrue);
  }

  test(
    'real GoTrue success clears pending before the auth event lands',
    () async {
      await start();

      await container.read(signInProvider.notifier).verifyCode('123456');

      expect(invites.calls, 1);
      expect(container.read(pendingInviteTokenProvider), isNull);
      expect(container.read(signInProvider).busy, isFalse);
    },
  );

  test('real GoTrue wrong-phone publishes its terminal notice', () async {
    await start();
    invites.failure = InviteFailure.wrongPhone;

    await container.read(signInProvider.notifier).verifyCode('123456');

    expect(invites.calls, 1);
    expect(
      container.read(inviteSignInNoticeProvider)?.message,
      contains('different number'),
    );
    expect(container.read(pendingInviteTokenProvider), isNull);
    expect(container.read(signInProvider).busy, isFalse);
  });

  test('real GoTrue success still lands after a token refresh', () async {
    await start();
    final hold = Completer<void>();
    invites.hold = hold;

    final verification = container
        .read(signInProvider.notifier)
        .verifyCode('123456');
    await pumpEventQueue();
    expect(invites.calls, 1);

    final accessTokenBeforeRefresh = goTrue.currentSession?.accessToken;
    await goTrue.refreshSession();
    await pumpEventQueue();
    expect(container.read(sessionProvider)?.user.id, userId);
    expect(goTrue.currentSession?.accessToken, isNot(accessTokenBeforeRefresh));
    hold.complete();
    await verification;

    expect(container.read(pendingInviteTokenProvider), isNull);
    expect(container.read(signInProvider).busy, isFalse);
  });
}
