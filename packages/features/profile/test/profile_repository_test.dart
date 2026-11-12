import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:settlo_profile/settlo_profile.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

void main() {
  test('loads the current profile and updates through the RPC', () async {
    final requests = <String>[];
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0)
      ..listen((request) async {
        final body = await utf8.decoder.bind(request).join();
        requests.add('${request.method} ${request.uri} $body');
        request.response.headers.contentType = ContentType.json;
        if (request.uri.path.endsWith('/profiles')) {
          request.response.write(
            jsonEncode({
              'name': 'Satheesh',
              'phone': '+919876543210',
              'upi_id': 'demo@upi',
            }),
          );
        } else {
          request.response.write('null');
        }
        await request.response.close();
      });
    addTearDown(() => server.close(force: true));
    final client = SupabaseClient(
      'http://${server.address.host}:${server.port}',
      'anon',
      authOptions: const AuthClientOptions(autoRefreshToken: false),
    );
    addTearDown(client.dispose);
    final repository = SupabaseProfileRepository(client, userId: 'u1');

    final profile = await repository.load();
    expect(
      (profile.name, profile.phone, profile.upiId),
      ('Satheesh', '+919876543210', 'demo@upi'),
    );
    await repository.update(name: 'Asha', upiId: null);
    expect(requests, hasLength(2));
    expect(requests.first, contains('/profiles?select=name%2Cphone%2Cupi_id'));
    expect(requests.first, contains('id=eq.u1'));
    expect(requests.last, contains('/rpc/update_profile'));
    expect(requests.last, contains('"p_name":"Asha"'));
    expect(requests.last, contains('"p_upi_id":null'));
    await repository.signOut();

    await repository.deleteAccount();
    expect(requests, hasLength(3));
    expect(requests.last, contains('POST /rest/v1/rpc/delete_account'));
  });

  // A server that answers each `delete_account` call with the next of
  // [answers]: null drops the connection, as a lost response does; a status
  // with a code is a PostgREST error; 204 is success.
  Future<(SupabaseProfileRepository, SupabaseClient, List<String>)> deleting(
    List<(int, String?)?> answers,
  ) async {
    final calls = <String>[];
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0)
      ..listen((request) async {
        calls.add(request.uri.path);
        final answer = answers[(calls.length - 1).clamp(0, answers.length - 1)];
        if (answer == null) {
          (await request.response.detachSocket()).destroy();
          return;
        }
        request.response
          ..statusCode = answer.$1
          ..headers.contentType = ContentType.json;
        if (answer.$2 case final code?) {
          request.response.write(jsonEncode({'code': code, 'message': 'raw'}));
        }
        await request.response.close();
      });
    addTearDown(() => server.close(force: true));
    final client = SupabaseClient(
      'http://${server.address.host}:${server.port}',
      'anon',
      authOptions: const AuthClientOptions(autoRefreshToken: false),
    );
    addTearDown(client.dispose);
    final repository = SupabaseProfileRepository(
      client,
      userId: 'u1',
      deleteRetryIn: Duration.zero,
    );
    return (repository, client, calls);
  }

  Future<bool> signedOutBy(SupabaseClient client, Future<void> work) async {
    var signedOut = false;
    final events = client.auth.onAuthStateChange.listen(
      (state) => signedOut |= state.event == AuthChangeEvent.signedOut,
    );
    try {
      await work;
    } finally {
      await pumpEventQueue();
      await events.cancel();
    }
    return signedOut;
  }

  test(
    'a lost delete response is retried, then the session is dropped',
    () async {
      final (repository, client, calls) = await deleting([null, (204, null)]);
      expect(await signedOutBy(client, repository.deleteAccount()), isTrue);
      expect(calls, hasLength(2), reason: 'asked again: the RPC is idempotent');
    },
  );

  test('a session the server no longer accepts counts as deleted', () async {
    for (final code in ['PGRST303', 'PGRST301', '42501']) {
      final (repository, client, calls) = await deleting([(401, code)]);
      expect(
        await signedOutBy(client, repository.deleteAccount()),
        isTrue,
        reason: code,
      );
      expect(calls, hasLength(1), reason: code);
    }
  });

  test('a delete that is refused or never answered stays signed in', () async {
    final (refused, refusedClient, _) = await deleting([(500, 'XX000')]);
    var signedOut = await signedOutBy(
      refusedClient,
      expectLater(refused.deleteAccount(), throwsA(isA<PostgrestException>())),
    );
    expect(signedOut, isFalse);

    final (silent, silentClient, calls) = await deleting([null]);
    signedOut = await signedOutBy(
      silentClient,
      expectLater(silent.deleteAccount(), throwsA(anything)),
    );
    expect(signedOut, isFalse);
    expect(calls, hasLength(3), reason: 'three tries, then the user decides');
  });

  test('server errors are translated only for 22023', () async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0)
      ..listen((request) async {
        final body = jsonDecode(await utf8.decoder.bind(request).join()) as Map;
        final name = body['p_name'];
        request.response
          ..statusCode = 400
          ..headers.contentType = ContentType.json
          ..write(
            jsonEncode({
              'code': name == 'Other' ? 'PGRST000' : '22023',
              'message': 'raw database validation detail',
              'hint': name == 'Asha' ? 'invalid_vpa' : null,
            }),
          );
        await request.response.close();
      });
    addTearDown(() => server.close(force: true));
    final client = SupabaseClient(
      'http://${server.address.host}:${server.port}',
      'anon',
      authOptions: const AuthClientOptions(autoRefreshToken: false),
    );
    addTearDown(client.dispose);
    final repository = SupabaseProfileRepository(client, userId: 'u1');

    await expectLater(
      repository.update(name: 'Asha', upiId: 'wrong'),
      throwsA(
        isA<ProfileInputException>().having(
          (error) => error.message,
          'message',
          upiValidationMessage,
        ),
      ),
    );
    await expectLater(
      repository.update(name: '', upiId: null),
      throwsA(
        isA<ProfileInputException>().having(
          (error) => error.message,
          'message',
          nameValidationMessage,
        ),
      ),
    );
    await expectLater(
      repository.update(name: 'Other', upiId: null),
      throwsA(isA<PostgrestException>()),
    );
  });
}
