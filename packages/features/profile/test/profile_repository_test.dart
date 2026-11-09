import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:settlo_profile/settlo_profile.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

void main() {
  test('server 22023 is translated to plain UPI copy', () async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0)
      ..listen((request) async {
        await utf8.decoder.bind(request).join();
        request.response
          ..statusCode = 400
          ..headers.contentType = ContentType.json
          ..write(
            jsonEncode({
              'code': '22023',
              'message': 'raw database validation detail',
              'hint': 'invalid_vpa',
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
  });
}
