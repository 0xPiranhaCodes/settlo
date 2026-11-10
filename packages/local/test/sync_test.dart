import 'dart:async';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:settlo_core/settlo_core.dart';
import 'package:settlo_local/settlo_local.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'fake_server.dart';

const _me = 'u-me';
const _at = '2026-11-01T00:00:00Z';
const _flat = <String, String?>{
  'name': 'Flat 7C',
  'kind': 'flat',
  'created_by': _me,
  'deleted_at': null,
};

/// No answer: the network is down.
const _offline = Refuse(null, status: 503);

Map<String, Object?> _member(
  String id,
  String phone, {
  String? user,
  String? name,
  String role = 'member',
}) => {
  'id': id,
  'space_id': 's1',
  'user_id': user,
  'name': name,
  'phone': phone,
  'role': role,
  'accepted_at': user == null ? null : _at,
  'left_at': null,
  'created_at': '2026-11-01T00:00:0${id.substring(1)}Z',
  'spaces': _flat,
};

NewExpense _groceries({
  String space = 's1',
  String payer = 'm1',
  List<String> members = const ['m1', 'm2', 'm3'],
  int amount = 3000,
}) => (
  spaceId: space,
  description: 'Groceries',
  category: 'food',
  amount: Paise(amount),
  spentOn: null,
  splitType: SplitType.equal,
  isSettlement: false,
  payers: {payer: Paise(amount)},
  splits: [
    for (final m in members)
      (
        memberId: m,
        amount: Paise(amount ~/ members.length),
        percentBp: null,
        shares: null,
      ),
  ],
);

void main() {
  late FakeServer server;
  late LocalDb db;
  late SyncEngine engine;
  late DateTime clock;
  late List<String> notices;
  late int changes;

  /// What the server stores, by key, and how often a write landed.
  late Map<String, String> landed;

  // add_expense on the server: payload-bound idempotency (ADR 0004).
  Object? addExpense(Map<String, dynamic> body) {
    final p = body['p'] as Map<String, dynamic>;
    final key = p['idempotency_key'] as String;
    if (landed[key] case final id?) return id;
    final id = landed[key] = 'e${landed.length + 1}';
    final balances = server.tables['space_member_balances']!;
    Map<String, Object?> row(Object? m) =>
        balances.firstWhere((b) => b['member_id'] == m);
    for (final payer in (p['payers'] as List).cast<Map<String, dynamic>>()) {
      final r = row(payer['member_id']);
      r['paid_minor'] =
          (r['paid_minor']! as int) + (payer['amount_minor'] as int);
      r['balance_minor'] =
          (r['balance_minor']! as int) + (payer['amount_minor'] as int);
    }
    for (final split in (p['splits'] as List).cast<Map<String, dynamic>>()) {
      final r = row(split['member_id']);
      r['balance_minor'] =
          (r['balance_minor']! as int) - (split['amount_minor'] as int);
    }
    return id;
  }

  SyncEngine engineWith({Duration wait = const Duration(seconds: 5)}) =>
      SyncEngine(
        db,
        server.client,
        owner: _me,
        now: () => clock,
        submitWait: wait,
        onChanged: () => changes++,
      )..notices.listen(notices.add);

  Future<int> myBalance() async => (await DriftSpacesRepository(
    engine,
    now: () => clock,
  ).load()).single.balance.value;

  setUp(() async {
    clock = DateTime(2026, 11, 10, 9);
    notices = [];
    changes = 0;
    landed = {};
    server = FakeServer();
    await server.start();
    server.tables.addAll({
      'space_members': [
        _member('m1', '+919000000001', user: _me, role: 'owner'),
        _member('m2', '+919000000002', user: 'u-rahul'),
        _member('m3', '+919000000003', name: 'Priya'),
      ],
      'space_member_balances': [
        for (final m in ['m1', 'm2', 'm3'])
          {
            'space_id': 's1',
            'member_id': m,
            'paid_minor': 0,
            'balance_minor': 0,
          },
      ],
      'profiles': [
        {'id': _me, 'name': 'Asha', 'phone': '+919000000001', 'upi_id': null},
        {'id': 'u-rahul', 'name': 'Rahul', 'phone': '+919000000002'},
      ],
    });
    db = LocalDb(NativeDatabase.memory());
    engine = engineWith();
    await engine.sync();
  });

  tearDown(() async {
    // Lets a sync still in flight finish before the database closes.
    final running = engine.sync();
    engine.dispose();
    await running;
    await db.close();
    await server.stop();
  });

  test('the first sync mirrors what the server shows', () async {
    expect(changes, 1);
    final spaces = await DriftSpacesRepository(engine).load();
    expect(spaces.single.name, 'Flat 7C');
    expect(
      [for (final m in spaces.single.members) m.name],
      ['Asha', 'Rahul', 'Priya'],
    );
  });

  test('a lost response is replayed with its key and counted once', () async {
    var first = true;
    server.rpc = (fn, body) {
      final id = addExpense(body);
      if (first) {
        first = false;
        return lost;
      }
      return id;
    };
    final id = await DriftExpensesRepository(engine)
        .add(_groceries(), idempotencyKey: 'k1');

    // The write landed but the phone never heard: it stays queued, shows
    // once, and the mirror is not refreshed under it.
    expect(id, 'local:k1');
    expect(landed, {'k1': 'e1'});
    expect(await myBalance(), 2000);
    expect((await db.mutations(_me)).single.attempts, 1);

    await engine.sync();

    expect(
      [
        for (final (fn, body) in server.calls)
          (fn, (body['p'] as Map)['idempotency_key']),
      ],
      [('add_expense', 'k1'), ('add_expense', 'k1')],
    );
    expect(landed, {'k1': 'e1'});
    expect(await db.mutations(_me), isEmpty);
    expect(await myBalance(), 2000);
  });

  test(
    'a write the server accepts shows until the refresh replaces it',
    () async {
      server
        ..rpc = ((fn, body) => addExpense(body))
        ..readStatus = 500;
      final id = await DriftExpensesRepository(engine)
          .add(_groceries(), idempotencyKey: 'k1');

      expect(id, 'e1');
      await engine.sync();
      expect((await db.mutations(_me)).single.applied, isTrue);
      expect(await myBalance(), 2000);

      server.readStatus = 200;
      await engine.sync();
      expect(await db.mutations(_me), isEmpty);
      expect(await myBalance(), 2000);
    },
  );

  test('a refusal after the sheet closed rolls back and says why', () async {
    server.rpc = (_, _) => _offline;
    await DriftExpensesRepository(engine)
        .add(_groceries(), idempotencyKey: 'k1');
    expect(await myBalance(), 2000);

    server.rpc = (_, _) => const Refuse('22023', hint: 'departed_member');
    changes = 0;
    await engine.sync();

    expect(await db.mutations(_me), isEmpty);
    expect(await myBalance(), 0);
    expect(changes, 1);
    await pumpEventQueue();
    expect(
      notices.single,
      '“Groceries” (₹30) couldn’t be saved because someone in it has left '
      'the space. We’ve undone it on this phone.',
    );
  });

  group('a refusal while the sheet waits is thrown and rolled back', () {
    for (final (name, refuse, matcher) in [
      ('invalid', const Refuse('22023'), isA<ExpenseRejected>()),
      (
        'pending settle-up',
        const Refuse('22023', hint: 'settlement_pending'),
        isA<SettlementPending>(),
      ),
      (
        'conflict',
        const Refuse('PT409', status: 409),
        isA<IdempotencyConflict>(),
      ),
    ]) {
      test(name, () async {
        server.rpc = (_, _) => refuse;
        await expectLater(
          DriftExpensesRepository(engine)
              .add(_groceries(), idempotencyKey: 'k1'),
          throwsA(matcher),
        );
        expect(await db.mutations(_me), isEmpty);
        expect(await myBalance(), 0);
        await pumpEventQueue();
        expect(notices, isEmpty);
      });
    }

    test('a changed settle-up', () async {
      server.rpc = (_, _) => const Refuse('22023', hint: 'settlement_changed');
      await expectLater(
        DriftSpaceLedgerRepository(engine).confirmSettlement(
          'e1',
          amount: const Paise(500),
          payerMemberId: 'm2',
          idempotencyKey: 'k1',
        ),
        throwsA(isA<SettlementChanged>()),
      );
    });

    test('anything else as the server sent it', () async {
      server.rpc = (_, _) => const Refuse('42501');
      await expectLater(
        DriftSpaceLedgerRepository(engine)
            .deleteExpense('e1', idempotencyKey: 'k1'),
        throwsA(isA<PostgrestException>()),
      );
    });
  });

  test('a slow server leaves the write queued and shown', () async {
    final answer = Completer<void>();
    engine.dispose();
    engine = engineWith(wait: Duration.zero);
    server.rpc = (_, _) => _offline;
    expect(
      await DriftExpensesRepository(engine)
          .add(_groceries(), idempotencyKey: 'k1'),
      'local:k1',
    );
    unawaited(engine.sync().whenComplete(answer.complete));
    await answer.future;
    expect(await myBalance(), 2000);
  });

  test(
    'a space made offline takes expenses that replay with real ids',
    () async {
      server.rpc = (_, _) => _offline;
      final spaces = DriftSpacesRepository(engine, now: () => clock);
      final id = await spaces.create(
        name: 'Goa',
        kind: SpaceKind.trip,
        members: const [
          (phone: '+919000000004', name: 'Bela'),
          (phone: '+919000000001', name: 'Me again'),
        ],
        idempotencyKey: 'space-1',
      );
      expect(id, 'space-1');
      final goa = (await spaces.load()).firstWhere((s) => s.id == id);
      expect(
        [for (final m in goa.members) (m.id, m.name, m.isYou)],
        [
          ('local:space-1:me', 'Asha', true),
          ('local:space-1:+919000000004', 'Bela', false),
        ],
      );

      final ledger = DriftSpaceLedgerRepository(engine, now: () => clock);
      await DriftExpensesRepository(engine).add(
        _groceries(
          space: id,
          payer: goa.you.id,
          members: [for (final m in goa.members) m.id],
          amount: 1000,
        ),
        idempotencyKey: 'k1',
      );
      final local = (await ledger.load(id)).expenses.single;
      expect(local.id, 'local:k1');
      await ledger.updateExpense((
        id: local.id,
        description: 'Dinner',
        category: null,
        amount: const Paise(2001),
        spentOn: local.spentOn,
        isSettlement: false,
        splitType: 'equal',
        payers: [(memberId: goa.you.id, amount: const Paise(2001))],
        splits: local.splits,
      ), idempotencyKey: 'k2');
      final edited = (await ledger.load(id)).expenses.single;
      expect([for (final s in edited.splits) s.amount.value], [1001, 1000]);
      expect((await spaces.load()).last.balance.value, 1000);

      server.rpc = (fn, body) {
        switch (fn) {
          case 'create_space':
            server.tables['space_members']!.addAll([
              {
                'id': 'g1',
                'space_id': 'space-1',
                'user_id': _me,
                'phone': '+919000000001',
              },
              {
                'id': 'g2',
                'space_id': 'space-1',
                'user_id': null,
                'phone': '+919000000004',
              },
            ]);
            return body['p_idempotency_key'];
          case 'add_expense':
            return 'e7';
        }
        return null;
      };
      await engine.sync();

      final [..., (create, _), (_, add), (_, update)] = server.calls;
      expect(create, 'create_space');
      final added = add['p'] as Map<String, dynamic>;
      expect(added['space_id'], 'space-1');
      expect(added['payers'], [
        {'member_id': 'g1', 'amount_minor': 1000},
      ]);
      expect(
        [for (final s in added['splits'] as List) (s as Map)['member_id']],
        ['g1', 'g2'],
      );
      expect((update['p'] as Map)['expense_id'], 'e7');
      expect(await db.mutations(_me), isEmpty);
    },
  );

  test('ids made on the phone still resolve after the refresh', () async {
    server.rpc = (fn, body) {
      if (fn == 'create_space') {
        server.tables['space_members']!.add({
          'id': 'g1',
          'space_id': 'space-1',
          'user_id': _me,
          'phone': '+919000000001',
        });
        return body['p_idempotency_key'];
      }
      return 'e7';
    };
    await DriftSpacesRepository(engine).create(
      name: 'Goa',
      kind: SpaceKind.trip,
      members: const [],
      idempotencyKey: 'space-1',
    );
    await engine.sync();
    expect(await db.mutations(_me), isEmpty);

    // A sheet opened before the refresh still holds the device-made id.
    await DriftExpensesRepository(engine).add(
      _groceries(
        space: 'space-1',
        payer: 'local:space-1:me',
        members: ['local:space-1:me'],
        amount: 1000,
      ),
      idempotencyKey: 'k1',
    );
    final (_, add) = server.calls.last;
    expect((add['p'] as Map)['payers'], [
      {'member_id': 'g1', 'amount_minor': 1000},
    ]);
  });

  test('a write that needs a refused one is refused too', () async {
    server.rpc = (_, _) => _offline;
    await DriftSpacesRepository(engine).create(
      name: 'Goa',
      kind: SpaceKind.trip,
      members: const [],
      idempotencyKey: 'space-1',
    );
    await DriftExpensesRepository(engine).add(
      _groceries(
        space: 'space-1',
        payer: 'local:space-1:me',
        members: ['local:space-1:me'],
        amount: 1000,
      ),
      idempotencyKey: 'k1',
    );
    server.rpc = (_, _) => const Refuse('42501');
    await engine.sync();
    await pumpEventQueue();
    const space =
        'The space “Goa” couldn’t be saved because you can’t change this '
        'space any more. We’ve undone it on this phone.';
    const groceries =
        '“Groceries” (₹10) couldn’t be saved because it depended on a change '
        'that wasn’t saved. We’ve undone it on this phone.';
    expect(notices, [space, groceries]);
    expect(server.calls.where((c) => c.$1 == 'add_expense'), isEmpty);
  });

  test('a write queued 40 days offline, first sent today, replays', () async {
    // Queued long ago and never sent: the server's key window has not begun.
    await db.enqueue(
      _me,
      'k1',
      'delete_expense',
      deleteExpenseParams('e1', idempotencyKey: 'k1'),
      clock.subtract(const Duration(days: 40)),
    );
    server.rpc = (_, _) => _offline;
    await engine.sync();
    server.rpc = (_, _) => null;
    await engine.sync();
    expect(server.calls, hasLength(2));
    expect(await db.mutations(_me), isEmpty);
    expect(notices, isEmpty);
  });

  test(
    'a write first sent 31 days ago is dropped, then the mirror refreshes',
    () async {
      server.rpc = (_, _) => _offline;
      await DriftSpaceLedgerRepository(engine)
          .deleteExpense('e1', idempotencyKey: 'k1');
      clock = clock.add(const Duration(days: 31));
      server.rpc = (_, _) => null;
      var reads = 0;
      server.onRead = () => reads++;
      await engine.sync();
      await pumpEventQueue();
      expect(server.calls, hasLength(1));
      expect(await db.mutations(_me), isEmpty);
      expect(reads, greaterThan(0));
      expect(
        notices.single,
        'Deleting that expense couldn’t be saved because it waited too long '
        'to reach the server. We’ve undone it on this phone.',
      );
    },
  );

  test('a retry keeps the first send as the start of the window', () async {
    server.rpc = (_, _) => _offline;
    await DriftSpaceLedgerRepository(engine)
        .deleteExpense('e1', idempotencyKey: 'k1');
    final first = clock;
    clock = clock.add(const Duration(days: 2));
    await engine.sync();
    final m = (await db.mutations(_me)).single;
    expect((m.attempts, m.firstAttemptAt), (2, first));
  });

  test('a failed send retries by itself with backoff', () async {
    server.rpc = (_, _) => _offline;
    await DriftExpensesRepository(engine)
        .add(_groceries(), idempotencyKey: 'k1');
    server.rpc = (fn, body) => addExpense(body);
    final end = DateTime.now().add(const Duration(seconds: 10));
    while ((await db.mutations(_me)).isNotEmpty) {
      if (DateTime.now().isAfter(end)) fail('never retried');
      await Future<void>.delayed(const Duration(milliseconds: 100));
    }
    expect(await myBalance(), 2000);
  });

  test('a sync asked for while one runs runs again after it', () async {
    final first = engine.sync();
    final second = engine.sync();
    await Future.wait([first, second]);
    expect(identical(first, second), isTrue);
    expect(await db.mutations(_me), isEmpty);
  });

  test('a disposed engine sends and writes nothing more', () async {
    server.rpc = (_, _) => _offline;
    await DriftExpensesRepository(engine)
        .add(_groceries(), idempotencyKey: 'k1');
    await engine.sync();
    engine.dispose();
    server.rpc = (_, _) => fail('sent after dispose');
    await engine.sync();
    expect((await db.mutations(_me)).single.applied, isFalse);
  });

  test('an answer that arrives after the database was wiped is dropped, '
      'even from an engine nobody disposed', () async {
    final held = Completer<Object?>();
    final sent = Completer<void>();
    server
      ..tables['space_members'] = [_member('m1', '+919000000001', user: _me)]
      ..rpc = (_, _) {
        sent.complete();
        return held.future;
      };
    await db.enqueue(_me, 's1', 'create_space', const {}, clock);
    final replay = engine.sync();
    await sent.future;
    await db.keepOnly(null);
    await db.keepOnly('u-next');
    held.complete('s1');
    await replay;
    expect(await db.localIds(_me), isEmpty);
    expect(await db.mirror(_me), isEmpty);
    // Nor does it take anything new.
    await expectLater(
      engine.submit('delete_expense', const {}, 'k2'),
      throwsStateError,
    );
    expect(await db.mutations(_me), isEmpty);
  });

  test('signing out mid-refresh writes no mirror', () async {
    server
      ..tables['profiles']!.first['name'] = 'Changed'
      ..onRead = engine.dispose;
    await engine.sync();
    final names = [
      for (final p in (await db.mirror(_me))['profiles']!) p['name'],
    ];
    expect(names, contains('Asha'));
  });

  test('a key is queued once, and only for one payload', () async {
    server.rpc = (_, _) => _offline;
    final expenses = DriftExpensesRepository(engine);
    await expenses.add(_groceries(), idempotencyKey: 'k1');
    await expenses.add(_groceries(), idempotencyKey: 'k1');
    expect(await db.mutations(_me), hasLength(1));
    await expectLater(
      expenses.add(_groceries(amount: 3300), idempotencyKey: 'k1'),
      throwsA(isA<IdempotencyConflict>()),
    );
    await expectLater(
      db.enqueue('u-other', 'k1', 'add_expense', const {}, clock),
      throwsA(isA<IdempotencyConflict>()),
    );
  });

  test('only the signed-in user keeps rows', () async {
    await db.enqueue('u-other', 'k9', 'delete_expense', const {}, clock);
    await db.replaceMirror('u-other', {'profiles': []});
    await db.keepOnly(_me);
    expect(await db.mutations('u-other'), isEmpty);
    expect(await db.mirror('u-other'), isEmpty);
    expect(await db.mirror(_me), isNotEmpty);
    await db.keepOnly(null);
    expect(await db.mirror(_me), isEmpty);
    expect(db.allTables, isEmpty);
  });

  test('a v1 queue upgrades in place, sent writes aged from enqueue', () async {
    final v1 = LocalDb(
      NativeDatabase.memory(
        setup: (raw) => raw
          ..execute(
            'CREATE TABLE mirror (owner TEXT NOT NULL, source TEXT NOT NULL, '
            'rows TEXT NOT NULL, PRIMARY KEY (owner, source))',
          )
          ..execute(
            'CREATE TABLE pending_mutations ( '
            'id INTEGER PRIMARY KEY AUTOINCREMENT, owner TEXT NOT NULL, '
            'idempotency_key TEXT NOT NULL UNIQUE, kind TEXT NOT NULL, '
            'payload TEXT NOT NULL, created_at INTEGER NOT NULL, '
            'attempts INTEGER NOT NULL DEFAULT 0, last_error TEXT, '
            "status TEXT NOT NULL DEFAULT 'pending')",
          )
          ..execute(
            'CREATE TABLE local_ids (owner TEXT NOT NULL, '
            'local_id TEXT NOT NULL, server_id TEXT NOT NULL, '
            'PRIMARY KEY (owner, local_id))',
          )
          ..execute(
            'INSERT INTO pending_mutations '
            '(owner, idempotency_key, kind, payload, created_at, attempts) '
            "VALUES ('$_me', 'k1', 'delete_expense', '{}', 1000, 0), "
            "('$_me', 'k2', 'delete_expense', '{}', 2000, 3)",
          )
          ..execute('PRAGMA user_version = 1'),
      ),
    );
    addTearDown(v1.close);
    expect(
      [for (final m in await v1.mutations(_me)) (m.key, m.firstAttemptAt)],
      [('k1', null), ('k2', DateTime.fromMillisecondsSinceEpoch(2000))],
    );
    await v1.markAttempted(1, clock);
    expect((await v1.mutations(_me)).first.firstAttemptAt, clock);
  });

  test('a ledger shows one space, categories largest first', () async {
    server.tables['space_monthly_categories'] = [
      for (final (space, category, total) in [
        ('s1', 'food', 100),
        ('s2', 'fuel', 900),
        ('s1', 'rent', 500),
      ])
        {
          'space_id': space,
          'month': '2026-11-01',
          'category': category,
          'total_minor': total,
          'expense_count': 1,
        },
    ];
    await engine.sync();
    final ledger = await DriftSpaceLedgerRepository(
      engine,
      now: () => clock,
    ).load('s1');
    expect([for (final c in ledger.categories) c.category], ['rent', 'food']);

    server.rpc = (_, _) => null;
    await DriftSpaceLedgerRepository(engine)
        .disputeSettlement('e1', 'Not received', idempotencyKey: 'k1');
    final (fn, body) = server.calls.single;
    expect(fn, 'dispute_settlement');
    expect(body, {
      'p_expense_id': 'e1',
      'p_reason': 'Not received',
      'p_idempotency_key': 'k1',
    });
  });
}
