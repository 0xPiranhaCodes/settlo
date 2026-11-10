import 'dart:convert';
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:settlo_core/settlo_core.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

void main() {
  test('builds the custom-scheme fallback until a host is configured', () {
    expect(inviteHttpsHost, isEmpty);
    expect(inviteLink('abc').toString(), 'settlo://join/abc');
  });

  group('Supabase adapter', () {
    late HttpServer server;
    late SupabaseClient client;
    late List<({String path, Map<String, dynamic> body})> requests;

    setUp(() async {
      requests = [];
      server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0)
        ..listen((request) async {
          final body = jsonDecode(await utf8.decoder.bind(request).join());
          final path = request.uri.path.replaceFirst('/rest/v1/rpc/', '');
          requests.add((path: path, body: body as Map<String, dynamic>));
          request.response.headers.contentType = ContentType.json;
          switch (path) {
            case 'inspect_invite':
              request.response.write(
                jsonEncode(
                  body['p_token'] == 'missing'
                      ? <Object?>[]
                      : [
                          {
                            'kind': 'space',
                            'inviter_name': 'Asha',
                            'subject_name': 'Flat 402',
                            'masked_phone': '+91910•••••02',
                          },
                        ],
                ),
              );
            case 'issue_invite':
              request.response.write(jsonEncode('issued-token'));
            default:
              if (body['p_token'] == 'wrong') {
                request.response
                  ..statusCode = HttpStatus.forbidden
                  ..write(
                    jsonEncode({
                      'code': '42501',
                      'message': 'wrong phone',
                      'details': null,
                      'hint': 'wrong_phone',
                    }),
                  );
              } else {
                request.response.statusCode = HttpStatus.noContent;
              }
          }
          await request.response.close();
        });
      client = SupabaseClient(
        'http://${server.address.host}:${server.port}',
        'anon',
        authOptions: const AuthClientOptions(autoRefreshToken: false),
      );
    });

    tearDown(() async {
      await client.dispose();
      await server.close(force: true);
    });

    test('maps minimal copy and sends every RPC contract', () async {
      final invites = SupabaseInvitesRepository(client);

      final preview = await invites.inspect('token');
      expect(preview?.kind, 'space');
      expect(preview?.inviterName, 'Asha');
      expect(preview?.subjectName, 'Flat 402');
      expect(preview?.maskedPhone, '+91910•••••02');
      expect(
        await invites.issueSpace('member', idempotencyKey: 'space-key'),
        'issued-token',
      );
      expect(
        await invites.issueLoan('loan', idempotencyKey: 'loan-key'),
        'issued-token',
      );
      await invites.redeem('token', idempotencyKey: 'redeem-key');
      await invites.decline('token', idempotencyKey: 'decline-key');

      expect(requests.map((request) => request.path), [
        'inspect_invite',
        'issue_invite',
        'issue_invite',
        'redeem_invite',
        'decline_invite',
      ]);
      expect(requests[1].body, {
        'p_kind': 'space',
        'p_subject_id': 'member',
        'p_idempotency_key': 'space-key',
      });
      expect(requests[2].body['p_kind'], 'loan');
      expect(requests[3].body['p_idempotency_key'], 'redeem-key');
      expect(requests[4].body, {
        'p_token': 'token',
        'p_idempotency_key': 'decline-key',
      });
    });

    test('maps unavailable copy to null', () async {
      expect(
        await SupabaseInvitesRepository(client).inspect('missing'),
        isNull,
      );
    });

    test('maps stable server hints to privacy-safe failures', () async {
      expect(
        () =>
            SupabaseInvitesRepository(client)
                .redeem('wrong', idempotencyKey: 'key'),
        throwsA(
          isA<InviteException>().having(
            (error) => error.failure,
            'failure',
            InviteFailure.wrongPhone,
          ),
        ),
      );
    });
  });

  test('providers build the adapter and remember a stable redemption key', () {
    final client = SupabaseClient('http://localhost', 'anon');
    addTearDown(client.dispose);
    final container = ProviderContainer(
      overrides: [supabaseClientProvider.overrideWithValue(client)],
    );
    addTearDown(container.dispose);

    expect(
      container.read(invitesRepositoryProvider),
      isA<SupabaseInvitesRepository>(),
    );
    container
        .read(pendingInviteTokenProvider.notifier)
        .remember('token', idempotencyKey: 'key');
    expect(container.read(pendingInviteTokenProvider)?.token, 'token');
    expect(container.read(pendingInviteTokenProvider)?.idempotencyKey, 'key');
    container.read(pendingInviteTokenProvider.notifier).clear();
    expect(container.read(pendingInviteTokenProvider), isNull);
  });
}
