import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:settlo_core/settlo_core.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// A session whose access token expires in 2100, so the client accepts it
/// without a refresh call.
Map<String, Object> _sessionJson() {
  String part(Map<String, Object> json) =>
      base64Url.encode(utf8.encode(jsonEncode(json))).replaceAll('=', '');
  final token = [
    part({'alg': 'HS256', 'typ': 'JWT'}),
    part({'sub': 'u1', 'exp': 4102444800}),
    'signature',
  ].join('.');
  return {
    'access_token': token,
    'token_type': 'bearer',
    'user': {
      'id': 'u1',
      'app_metadata': <String, Object>{},
      'user_metadata': <String, Object>{},
      'aud': 'authenticated',
      'created_at': '2026-11-09T00:00:00Z',
    },
  };
}

void main() {
  group('SupabaseConfig', () {
    test('keeps the URL and key', () {
      final config = SupabaseConfig.from(url: 'http://x', anonKey: 'k');
      expect((config.url, config.anonKey), ('http://x', 'k'));
    });

    test('names every missing key', () {
      expect(
        () => SupabaseConfig.from(url: '', anonKey: ''),
        throwsA(
          isA<StateError>().having(
            (e) => e.message,
            'message',
            allOf(
              contains('SUPABASE_URL and SUPABASE_ANON_KEY'),
              contains('--dart-define-from-file'),
            ),
          ),
        ),
      );
    });

    test('is not compiled into test builds', () {
      expect(SupabaseConfig.fromEnvironment, throwsStateError);
    });
  });

  test('the client provider needs Supabase initialised', () {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    expect(() => container.read(supabaseClientProvider), throwsA(anything));
  });

  test('the session follows the client auth state', () async {
    final client = SupabaseClient(
      'http://localhost:54321',
      'anon',
      authOptions: const AuthClientOptions(autoRefreshToken: false),
    );
    final container = ProviderContainer(
      overrides: [supabaseClientProvider.overrideWithValue(client)],
    );
    addTearDown(container.dispose);
    final seen = <String?>[];
    container.listen(
      sessionProvider,
      (_, session) => seen.add(session?.user.id),
      fireImmediately: true,
    );

    await client.auth.setInitialSession(jsonEncode(_sessionJson()));
    await Future<void>.delayed(Duration.zero);

    expect(seen, [null, 'u1']);
    expect(container.read(sessionProvider)?.user.id, 'u1');
  });
}
