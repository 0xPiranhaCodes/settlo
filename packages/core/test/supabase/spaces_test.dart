import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:settlo_core/settlo_core.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

const _me = 'u-me';
const _at = '2026-11-01T10:00:00Z';

/// A key the server already holds with a different payload.
const _usedKey = '00000000-0000-4000-8000-000000000409';

const _spaces = <String, Map<String, String?>>{
  's1': {'name': 'Flat 402', 'kind': 'flat', 'deleted_at': null},
  's2': {'name': 'New', 'kind': 'trip', 'deleted_at': null},
  's3': {'name': 'Old flat', 'kind': 'flat', 'deleted_at': _at},
  's4': {'name': 'Claim', 'kind': 'other', 'deleted_at': null},
  's5': {'name': 'Left', 'kind': 'other', 'deleted_at': null},
  's6': {'name': 'Shared', 'kind': 'other', 'deleted_at': null},
};

Map<String, Object?> _member(
  String id,
  String space, {
  String? user,
  String? name,
  String phone = '+919000000000',
  bool owner = false,
  bool accepted = true,
  bool left = false,
}) => {
  'id': id,
  'space_id': space,
  'user_id': user,
  'name': name,
  'phone': phone,
  'role': owner ? 'owner' : 'member',
  'accepted_at': user != null && accepted ? _at : null,
  'left_at': left ? _at : null,
  'spaces': _spaces[space],
};

/// Rows as PostgREST returns them to the signed-in user under RLS.
final _tables = <String, List<Map<String, Object?>>>{
  'space_members': [
    _member('m1', 's1', user: _me, owner: true, phone: '+919876543210'),
    _member('m2', 's1', user: 'u-rahul', phone: '+919100000001'),
    _member('m3', 's1', name: 'Priya', phone: '+919100000002'),
    _member('m4', 's1', name: 'Gone', left: true),
    _member('m5', 's2', user: _me, owner: true),
    _member('m6', 's3', user: _me),
    _member('m7', 's4', user: _me, accepted: false),
    _member('m8', 's5', user: _me, left: true),
    // Arun paid the only expense, then left; you paid nothing.
    _member('m11', 's6', user: _me),
    _member('m12', 's6', user: 'u-arun', name: 'Arun', left: true),
    _member('m13', 's6', name: 'Bela'),
  ],
  'space_member_balances': [
    {'member_id': 'm1', 'paid_minor': 900000, 'balance_minor': 285000},
    {'member_id': 'm2', 'paid_minor': 0, 'balance_minor': -285000},
    {'member_id': 'm5', 'paid_minor': 0, 'balance_minor': 0},
    {'member_id': 'm11', 'paid_minor': 0, 'balance_minor': -33333},
    {'member_id': 'm12', 'paid_minor': 100000, 'balance_minor': 66666},
    {'member_id': 'm13', 'paid_minor': 0, 'balance_minor': -33333},
  ],
  'space_monthly_fairness': [
    {
      'member_id': 'm1',
      'paid_minor': 900000,
      'fair_share_minor': 615000,
      'month_total_minor': 1845000,
    },
    {
      'member_id': 'm2',
      'paid_minor': 540000,
      'fair_share_minor': 615000,
      'month_total_minor': 1845000,
    },
    for (final (id, paid, fair) in [
      ('m11', 0, 33333),
      ('m12', 100000, 33334),
      ('m13', 0, 33333),
    ])
      {
        'member_id': id,
        'paid_minor': paid,
        'fair_share_minor': fair,
        'month_total_minor': 100000,
      },
  ],
  // You paid Arun ₹100 that he has not confirmed; Bela's to Arun is hers.
  'pending_settlements': [
    {'payer_member_id': 'm11', 'payee_member_id': 'm12', 'amount_minor': 10000},
    {'payer_member_id': 'm13', 'payee_member_id': 'm12', 'amount_minor': 5000},
  ],
  'profiles': [
    {'id': _me, 'name': 'Sana'},
    {'id': 'u-rahul', 'name': 'Rahul', 'upi_id': 'demo@upi'},
  ],
};

void main() {
  late HttpServer server;
  late SupabaseClient client;
  late List<String> requests;

  setUp(() async {
    requests = [];
    server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0)
      ..listen((request) async {
        final body = await utf8.decoder.bind(request).join();
        final path = request.uri.path.replaceFirst('/rest/v1/', '');
        requests.add(
          '${request.method} $path ${request.uri.query}'
          '${body.isEmpty ? '' : ' $body'}',
        );
        final key = path.startsWith('rpc/')
            ? (jsonDecode(body) as Map)['p_idempotency_key']
            : null;
        if (key == _usedKey) {
          request.response
            ..statusCode = 409
            ..headers.contentType = ContentType.json
            ..write(
              jsonEncode({
                'code': 'PT409',
                'message': 'idempotency key reused',
                'hint': 'idempotency_conflict',
              }),
            );
        } else {
          request.response
            ..headers.contentType = ContentType.json
            ..write(jsonEncode(key ?? _tables[path]));
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

  SpacesRepository repository() => SupabaseSpacesRepository(
    client,
    userId: _me,
    now: () => DateTime(2026, 11, 9, 23, 59),
  );

  test('lists accepted spaces with members, balances and the month', () async {
    final spaces = await repository().load();

    expect(
      requests,
      contains(
        startsWith(
          'GET space_monthly_fairness '
          'select=member_id%2Cpaid_minor%2Cfair_share_minor%2C'
          'month_total_minor&month=eq.2026-11-01',
        ),
      ),
    );
    // Deleted spaces, spaces you left and unaccepted claims are left out.
    expect([for (final s in spaces) s.id], ['s1', 's2', 's6']);

    final flat = spaces.first;
    expect(
      (flat.name, flat.kind, flat.month, flat.hasExpenses),
      ('Flat 402', SpaceKind.flat, DateTime(2026, 11), true),
    );
    expect(
      (flat.monthTotal.value, flat.yourFairShare.value, flat.balance.value),
      (1845000, 615000, 285000),
    );
    // Members who left are gone; labels fall back from the creator's label
    // to the profile name to the number.
    expect(
      [
        for (final m in flat.members)
          (
            m.name,
            m.isYou,
            m.isOwner,
            m.joined,
            m.balance.value,
            m.monthPaid.value,
          ),
      ],
      [
        ('Sana', true, true, true, 285000, 900000),
        ('Rahul', false, false, true, -285000, 540000),
        ('Priya', false, false, false, 0, 0),
      ],
    );
    expect(flat.others.map((m) => m.name), ['Rahul', 'Priya']);
    expect(flat.departed.map((m) => m.name), ['Gone']);
    // A UPI id comes from the joined member's profile.
    expect(
      [for (final m in flat.members) m.upiId],
      [null, 'demo@upi', null],
    );
    expect(
      [for (final p in flat.payments) (p.from.name, p.to.name, p.amount.value)],
      [('Rahul', 'Sana', 285000)],
    );

    final fresh = spaces[1];
    expect((fresh.hasExpenses, fresh.monthTotal), (false, Paise.zero));
    expect(fresh.members.single.isYou, isTrue);
    expect(fresh.departed, isEmpty);
  });

  test('a member who left still counts in history and the month', () async {
    final shared = (await repository().load()).last;

    // The only payer left and you paid nothing: the space is not empty.
    expect(shared.hasExpenses, isTrue);
    expect(shared.balance.value, -33333);
    expect(shared.you.monthPaid, Paise.zero);
    expect(shared.others.map((m) => m.name), ['Bela']);
    expect(
      [for (final m in shared.departed) (m.name, m.monthPaid.value)],
      [('Arun', 100000)],
    );
    expect(
      (shared.monthTotal.value, shared.yourFairShare.value),
      (100000, 33333),
    );
    // Both still pay Arun, so two payments for three people. Your pending
    // ₹100 is not offered again; Bela's pending one is not yours to net.
    expect(
      [
        for (final p in shared.pendingFromYou)
          (p.from.name, p.to.name, p.amount.value),
      ],
      [('Sana', 'Arun', 10000)],
    );
    expect(shared.balance.value, -33333, reason: 'balances stay confirmed');
    expect(
      [
        for (final p in shared.payments)
          (p.from.name, p.to.name, p.amount.value),
      ],
      [('Bela', 'Arun', 33333), ('Sana', 'Arun', 23333)],
    );
  });

  test('creates a space through create_space with the key', () async {
    final id = await repository().create(
      name: 'Flat 402',
      kind: SpaceKind.flat,
      members: const [(phone: '+919100000002', name: 'Priya')],
      idempotencyKey: '6f1c2e3a-8d4b-4f6e-9a1b-2c3d4e5f6a7b',
    );

    expect(id, '6f1c2e3a-8d4b-4f6e-9a1b-2c3d4e5f6a7b');
    final body = jsonEncode({
      'p_name': 'Flat 402',
      'p_kind': 'flat',
      'p_members': [
        {'phone': '+919100000002', 'name': 'Priya'},
      ],
      'p_idempotency_key': '6f1c2e3a-8d4b-4f6e-9a1b-2c3d4e5f6a7b',
    });
    expect(requests, ['POST rpc/create_space  $body']);
  });

  test('a key reused with a different payload is a conflict', () async {
    await expectLater(
      repository().create(
        name: 'Flat 402',
        kind: SpaceKind.flat,
        members: const [],
        idempotencyKey: _usedKey,
      ),
      throwsA(isA<IdempotencyConflict>()),
    );
  });

  test('adds people through add_space_members with the key', () async {
    await repository().addMembers('s1', const [
      (phone: '+919100000009', name: 'Xavier'),
    ], idempotencyKey: 'k-add');

    final body = jsonEncode({
      'p_space_id': 's1',
      'p_members': [
        {'phone': '+919100000009', 'name': 'Xavier'},
      ],
      'p_idempotency_key': 'k-add',
    });
    expect(requests, ['POST rpc/add_space_members  $body']);
    await expectLater(
      repository().addMembers('s1', const [], idempotencyKey: _usedKey),
      throwsA(isA<IdempotencyConflict>()),
    );
  });

  test('idempotency keys are v4 UUIDs, fresh each time', () {
    final uuid = RegExp(
      r'^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$',
    );
    final keys = {for (var i = 0; i < 100; i++) newIdempotencyKey()};
    expect(keys, hasLength(100));
    expect(keys, everyElement(matches(uuid)));
    expect(newIdempotencyKey(Random(1)), newIdempotencyKey(Random(1)));
  });

  group('spacesRepositoryProvider', () {
    test('needs a signed-in user', () {
      final container = ProviderContainer(
        overrides: [
          supabaseClientProvider.overrideWithValue(client),
          sessionProvider.overrideWith(_NoSession.new),
        ],
      );
      addTearDown(container.dispose);
      expect(() => container.read(spacesRepositoryProvider), throwsA(anything));
    });

    test('reads as the signed-in user', () {
      final container = ProviderContainer(
        overrides: [
          supabaseClientProvider.overrideWithValue(client),
          sessionProvider.overrideWith(_SignedIn.new),
        ],
      );
      addTearDown(container.dispose);
      expect(
        container.read(spacesRepositoryProvider),
        isA<SupabaseSpacesRepository>().having((r) => r.userId, 'userId', _me),
      );
    });
  });
}

class _NoSession extends SessionNotifier {
  @override
  Session? build() => null;
}

class _SignedIn extends SessionNotifier {
  @override
  Session? build() => Session(
    accessToken: 't',
    tokenType: 'bearer',
    user: const User(
      id: _me,
      appMetadata: {},
      userMetadata: {},
      aud: 'authenticated',
      createdAt: _at,
    ),
  );
}
