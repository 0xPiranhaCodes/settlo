import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:settlo_core/settlo_core.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

const _me = 'u-me';

/// A key the server already holds with a different payload.
const _usedKey = '00000000-0000-4000-8000-000000000409';

Map<String, Object?> _split(String member, int amount, String joined) => {
  'member_id': member,
  'split_type': 'equal',
  'amount_minor': amount,
  'shares': null,
  'percent_bp': null,
  'space_members': {'created_at': joined},
};

/// Rows as PostgREST returns them to a member under RLS.
final _tables = <String, List<Map<String, Object?>>>{
  'expenses': [
    {
      'id': 'e1',
      'description': 'Groceries',
      'category': 'food',
      'amount_minor': 10000,
      'spent_on': '2026-11-09',
      'is_settlement': false,
      'created_by': _me,
      'deleted_at': null,
      'expense_payers': [
        {'member_id': 'm2', 'amount_minor': 10000},
      ],
      // Out of member order, as PostgREST may return them.
      'expense_splits': [
        _split('m3', 3333, '2026-11-01T10:02:00Z'),
        _split('m1', 3333, '2026-11-01T10:00:00Z'),
        _split('m2', 3334, '2026-11-01T10:01:00Z'),
      ],
    },
    {
      'id': 'e2',
      'description': 'Deleted',
      'category': null,
      'amount_minor': 500,
      'spent_on': '2026-11-08',
      'is_settlement': false,
      'created_by': 'u-rahul',
      'deleted_at': '2026-11-09T08:00:00Z',
      'expense_payers': [
        {'member_id': 'm2', 'amount_minor': 500},
      ],
      'expense_splits': [_split('m2', 500, '2026-11-01T10:01:00Z')],
    },
    {
      'id': 'e4',
      'description': 'Rahul paid you back',
      'category': null,
      'amount_minor': 50000,
      'spent_on': '2026-11-07',
      'is_settlement': true,
      'settlement_status': 'disputed',
      'dispute_reason': 'Not received',
      'created_by': _me,
      'deleted_at': null,
      'expense_payers': [
        {'member_id': 'm2', 'amount_minor': 50000},
      ],
      'expense_splits': [
        {..._split('m1', 50000, '2026-11-01T10:00:00Z'), 'split_type': 'exact'},
      ],
    },
    {
      'id': 'e3',
      'description': 'Wifi',
      'category': null,
      'amount_minor': 119900,
      'spent_on': '2026-11-08',
      'is_settlement': false,
      'created_by': 'u-rahul',
      'deleted_at': null,
      'expense_payers': [
        {'member_id': 'm2', 'amount_minor': 119900},
      ],
      'expense_splits': [
        {
          ..._split('m1', 59950, '2026-11-01T10:00:00Z'),
          'split_type': 'shares',
          'shares': 1,
        },
        {
          ..._split('m2', 59950, '2026-11-01T10:01:00Z'),
          'split_type': 'shares',
          'shares': 1,
        },
      ],
    },
  ],
  'space_monthly_fairness': [
    {'member_id': 'm1', 'paid_minor': 900000, 'fair_share_minor': 615000},
    {'member_id': 'm2', 'paid_minor': 540000, 'fair_share_minor': 615000},
  ],
  'space_monthly_categories': [
    {'category': 'food', 'total_minor': 10000, 'expense_count': 1},
    {'category': null, 'total_minor': 119900, 'expense_count': 1},
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
        if (body.contains(_usedKey)) {
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
        } else if (path.startsWith('rpc/')) {
          request.response.statusCode = 204;
        } else {
          request.response
            ..headers.contentType = ContentType.json
            ..write(jsonEncode(_tables[path]));
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

  SpaceLedgerRepository repository() => SupabaseSpaceLedgerRepository(
    client,
    userId: _me,
    now: () => DateTime(2026, 11, 9, 23, 59),
  );

  test('loads live expenses and this month for one space', () async {
    final ledger = await repository().load('s1');

    expect(
      requests,
      containsAll([
        allOf(
          startsWith('GET expenses '),
          contains('space_id=eq.s1'),
          contains('deleted_at=is.null'),
        ),
        allOf(
          startsWith('GET space_monthly_fairness '),
          contains('space_id=eq.s1&month=eq.2026-11-01'),
        ),
        allOf(
          startsWith('GET space_monthly_categories '),
          contains('space_id=eq.s1&month=eq.2026-11-01'),
        ),
      ]),
    );
    expect(
      (ledger.today, ledger.month),
      (DateTime(2026, 11, 9), DateTime(2026, 11)),
    );
    // A soft-deleted row is hidden even if the filter is missed.
    expect([for (final e in ledger.expenses) e.id], ['e1', 'e4', 'e3']);
    expect(
      [for (final e in ledger.expenses) e.isSettlement],
      [false, true, false],
    );
    expect(
      [for (final e in ledger.expenses) (e.settlementStatus, e.disputeReason)],
      [(null, null), (SettlementStatus.disputed, 'Not received'), (null, null)],
    );

    final groceries = ledger.expenses.first;
    expect(
      (
        groceries.description,
        groceries.category,
        groceries.amount.value,
        groceries.spentOn,
        groceries.splitType,
        groceries.createdByYou,
      ),
      ('Groceries', 'food', 10000, DateTime(2026, 11, 9), 'equal', true),
    );
    expect(groceries.payers, [(memberId: 'm2', amount: const Paise(10000))]);
    // Splits come back in member order.
    expect([for (final s in groceries.splits) s.memberId], ['m1', 'm2', 'm3']);

    final wifi = ledger.expenses.last;
    expect((wifi.splitType, wifi.createdByYou), ('shares', false));
    expect(wifi.splits.first.shares, 1);

    expect(ledger.fairness['m1'], (
      paid: const Paise(900000),
      fairShare: const Paise(615000),
    ));
    expect(ledger.categories, [
      (category: 'food', total: const Paise(10000), count: 1),
      (category: null, total: const Paise(119900), count: 1),
    ]);
  });

  test('edits through update_expense with the key', () async {
    final wifi = (await repository().load('s1')).expenses.last;
    requests.clear();

    await repository().updateExpense((
      id: wifi.id,
      description: 'Wifi · Airtel',
      category: wifi.category,
      amount: wifi.amount,
      spentOn: wifi.spentOn,
      isSettlement: wifi.isSettlement,
      splitType: wifi.splitType,
      payers: wifi.payers,
      splits: wifi.splits,
    ), idempotencyKey: '5d2e0000-0000-4000-8000-000000000001');

    final body = jsonEncode({
      'p': {
        'expense_id': 'e3',
        'idempotency_key': '5d2e0000-0000-4000-8000-000000000001',
        'description': 'Wifi · Airtel',
        'category': null,
        'amount_minor': 119900,
        'spent_on': '2026-11-08',
        'is_settlement': false,
        'split_type': 'shares',
        'payers': [
          {'member_id': 'm2', 'amount_minor': 119900},
        ],
        'splits': [
          {'member_id': 'm1', 'amount_minor': 59950, 'shares': 1},
          {'member_id': 'm2', 'amount_minor': 59950, 'shares': 1},
        ],
      },
    });
    expect(requests, ['POST rpc/update_expense  $body']);
  });

  test('an equal split sends members only, for the server to divide', () async {
    final groceries = (await repository().load('s1')).expenses.first;
    requests.clear();

    await repository().updateExpense((
      id: groceries.id,
      description: groceries.description,
      category: groceries.category,
      amount: const Paise(12000),
      spentOn: groceries.spentOn,
      isSettlement: false,
      splitType: 'equal',
      payers: [(memberId: 'm2', amount: const Paise(12000))],
      splits: groceries.splits,
    ), idempotencyKey: '5d2e0000-0000-4000-8000-000000000002');

    final p = (jsonDecode(requests.single.split('  ').last) as Map)['p'] as Map;
    expect(p['amount_minor'], 12000);
    expect(p['payers'], [
      {'member_id': 'm2', 'amount_minor': 12000},
    ]);
    expect(p['splits'], [
      {'member_id': 'm1'},
      {'member_id': 'm2'},
      {'member_id': 'm3'},
    ]);
  });

  test('editing a settle-up keeps it a settle-up', () async {
    final settleUp = (await repository().load('s1')).expenses[1];
    requests.clear();

    await repository().updateExpense((
      id: settleUp.id,
      description: 'Rahul paid you back in cash',
      category: settleUp.category,
      amount: settleUp.amount,
      spentOn: settleUp.spentOn,
      isSettlement: settleUp.isSettlement,
      splitType: settleUp.splitType,
      payers: settleUp.payers,
      splits: settleUp.splits,
    ), idempotencyKey: '5d2e0000-0000-4000-8000-000000000004');

    // update_expense resets an omitted is_settlement to false, which would
    // start counting the transfer as spending (docs/api.md).
    final p = (jsonDecode(requests.single.split('  ').last) as Map)['p'] as Map;
    expect((p['expense_id'], p['is_settlement']), ('e4', true));
  });

  test('deletes through delete_expense with the key', () async {
    await repository().deleteExpense(
      'e1',
      idempotencyKey: '8a1f0000-0000-4000-8000-000000000003',
    );

    final body = jsonEncode({
      'p_expense_id': 'e1',
      'p_idempotency_key': '8a1f0000-0000-4000-8000-000000000003',
    });
    expect(requests, ['POST rpc/delete_expense  $body']);
  });

  test('a key reused with a different payload is a conflict', () async {
    await expectLater(
      repository().deleteExpense('e1', idempotencyKey: _usedKey),
      throwsA(isA<IdempotencyConflict>()),
    );
  });

  test('the payee confirms or disputes through the settlement RPCs', () async {
    await repository().confirmSettlement(
      'e4',
      amount: const Paise(50000),
      payerMemberId: 'm2',
      idempotencyKey: 'c2d40000-0000-4000-8000-000000000005',
    );
    await repository().disputeSettlement(
      'e4',
      'Not received',
      idempotencyKey: 'e5f60000-0000-4000-8000-000000000006',
    );

    expect(requests, [
      'POST rpc/confirm_settlement  ${jsonEncode({'p_expense_id': 'e4', 'p_amount_minor': 50000, 'p_payer_member_id': 'm2', 'p_idempotency_key': 'c2d40000-0000-4000-8000-000000000005'})}',
      'POST rpc/dispute_settlement  ${jsonEncode({'p_expense_id': 'e4', 'p_reason': 'Not received', 'p_idempotency_key': 'e5f60000-0000-4000-8000-000000000006'})}',
    ]);
  });
}
