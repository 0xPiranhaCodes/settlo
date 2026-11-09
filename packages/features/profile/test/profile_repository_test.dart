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
              'upi_id': 'satheesh@okaxis',
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
      ('Satheesh', '+919876543210', 'satheesh@okaxis'),
    );
    await repository.update(name: 'Asha', upiId: null);
    expect(requests, hasLength(2));
    expect(requests.first, contains('/profiles?select=name%2Cphone%2Cupi_id'));
    expect(requests.first, contains('id=eq.u1'));
    expect(requests.last, contains('/rpc/update_profile'));
    expect(requests.last, contains('"p_name":"Asha"'));
    expect(requests.last, contains('"p_upi_id":null'));
    await repository.signOut();
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
