import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:settlo_core/settlo_core.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

const _key = '0b9d7c1e-2f3a-4b5c-8d6e-7f8a9b0c1d2e';

/// ₹100.00 paid by Bilal, split equally between three (docs/api.md).
const NewExpense _groceries = (
  spaceId: 's1',
  description: 'Groceries',
  category: 'food',
  amount: Paise(10000),
  spentOn: null,
  splitType: SplitType.equal,
  payers: {'bilal': Paise(10000)},
  splits: [
    (memberId: 'asha', amount: Paise(3333), percentBp: null, shares: null),
    (memberId: 'bilal', amount: Paise(3334), percentBp: null, shares: null),
    (memberId: 'xavier', amount: Paise(3333), percentBp: null, shares: null),
  ],
);

void main() {
  late HttpServer server;
  late SupabaseClient client;
  late List<String> bodies;
  late Map<String, String> stored;

  /// What the server does with the next request; it then answers normally.
  late String next;

  setUp(() async {
    bodies = [];
    stored = {};
    next = 'answer';
    server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0)
      ..listen((request) async {
        final body = await utf8.decoder.bind(request).join();
        bodies.add(body);
        final p = (jsonDecode(body) as Map)['p'] as Map;
        final key = p['idempotency_key'] as String;
        final (status, reply) = switch (next) {
          'reject' => (400, {'code': '22023', 'message': 'sums'}),
          _ when (stored[key] ?? body) != body => (
            409,
            {'code': 'PT409', 'hint': 'idempotency_conflict'},
          ),
          // Same key and payload returns the original id.
          _ => (200, 'e-${(stored..putIfAbsent(key, () => body)).length}'),
        };
        final action = next;
        next = 'answer';
        if (action == 'drop') {
          // Committed, then the connection died before the reply.
          final socket = await request.response.detachSocket(
            writeHeaders: false,
          );
          socket.destroy();
          return;
        }
        request.response
          ..statusCode = status
          ..headers.contentType = ContentType.json
          ..write(jsonEncode(reply));
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

  SupabaseExpensesRepository repository() => SupabaseExpensesRepository(client);

  test('sends add_expense as docs/api.md describes it', () async {
    final id = await repository().add(_groceries, idempotencyKey: _key);

    expect(id, 'e-1');
    expect(jsonDecode(bodies.single), {
      'p': {
        'idempotency_key': _key,
        'space_id': 's1',
        'description': 'Groceries',
        'category': 'food',
        'amount_minor': 10000,
        'split_type': 'equal',
        'payers': [
          {'member_id': 'bilal', 'amount_minor': 10000},
        ],
        'splits': [
          {'member_id': 'asha', 'amount_minor': 3333},
          {'member_id': 'bilal', 'amount_minor': 3334},
          {'member_id': 'xavier', 'amount_minor': 3333},
        ],
      },
    });
  });

  test('sends percent_bp, shares and spent_on when set', () async {
    await repository().add((
      spaceId: 's1',
      description: 'Rent',
      category: null,
      amount: const Paise(101),
      spentOn: DateTime(2026, 11, 3),
      splitType: SplitType.percent,
      payers: const {'asha': Paise(101)},
      splits: const [
        (memberId: 'asha', amount: Paise(51), percentBp: 5000, shares: 2),
        (memberId: 'bilal', amount: Paise(50), percentBp: 5000, shares: null),
      ],
    ), idempotencyKey: _key);

    final p = (jsonDecode(bodies.single) as Map)['p'] as Map;
    expect(p.containsKey('category'), isFalse);
    expect(p['spent_on'], '2026-11-03');
    expect(p['split_type'], 'percent');
    expect(p['splits'], [
      {
        'member_id': 'asha',
        'amount_minor': 51,
        'percent_bp': 5000,
        'shares': 2,
      },
      {'member_id': 'bilal', 'amount_minor': 50, 'percent_bp': 5000},
    ]);
  });

  test(
    'a retry after a dropped reply reuses the key and records once',
    () async {
      next = 'drop';
      await expectLater(
        repository().add(_groceries, idempotencyKey: _key),
        throwsA(anything),
      );

      final id = await repository().add(_groceries, idempotencyKey: _key);

      expect(id, 'e-1');
      expect(stored, hasLength(1));
      expect(bodies, hasLength(2));
      expect(bodies.first, bodies.last, reason: 'same key, same payload');
    },
  );

  test('PT409: the key was used with different details', () async {
    await repository().add(_groceries, idempotencyKey: _key);
    await expectLater(
      repository().add((
        spaceId: _groceries.spaceId,
        description: 'Groceries and milk',
        category: _groceries.category,
        amount: _groceries.amount,
        spentOn: null,
        splitType: _groceries.splitType,
        payers: _groceries.payers,
        splits: _groceries.splits,
      ), idempotencyKey: _key),
      throwsA(isA<IdempotencyConflict>()),
    );
  });

  test('22023: the server refused the payload', () async {
    next = 'reject';
    await expectLater(
      repository().add(_groceries, idempotencyKey: _key),
      throwsA(isA<ExpenseRejected>()),
    );
  });
}
