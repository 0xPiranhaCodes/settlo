import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:settlo_core/settlo_core.dart';
import 'package:settlo_local/settlo_local.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'fake_server.dart';

const _me = 'u-me';
const _at = '2026-11-01T00:00:00+00:00';

/// No answer: the network is down.
const _offline = Refuse(null, status: 503);

const _spaceClaim = Claim(
  kind: ClaimKind.spaceMember,
  id: 'm9',
  title: 'Goa trip',
  recordedBy: 'Rahul',
  amount: Paise.zero,
);
const _loanClaim = Claim(
  kind: ClaimKind.loan,
  id: 'l2',
  title: 'Rahul',
  recordedBy: 'Rahul',
  amount: Paise(50000),
);

NewLoan _newLoan({int? installment = 10000}) => (
  youLent: true,
  counterpartyPhone: '+919000000004',
  principal: const Paise(25000),
  installment: installment == null ? null : Paise(installment),
  dueDay: installment == null ? null : 5,
  startOn: DateTime(2026, 11, 10),
);

Map<String, Object?> _activity(int id) => {
  'id': id,
  'created_at': '2026-11-01T00:00:00+00:00',
  'action': 'created',
  'kind': 'expense',
  'by_me': true,
  'description': 'Entry $id',
  'amount_minor': 100,
};

void main() {
  late FakeServer server;
  late LocalDb db;
  late SyncEngine engine;
  late DateTime clock;
  late List<String> notices;

  /// Keys whose write landed on the server, and how often.
  late Map<String, int> landed;

  // The loan RPCs on the server: a replayed key writes nothing.
  Object? loanRpc(String fn, Map<String, dynamic> body) {
    final p = (body['p'] as Map<String, dynamic>?) ?? body;
    final key = (p['idempotency_key'] ?? p['p_idempotency_key']) as String;
    landed[key] = (landed[key] ?? 0) + 1;
    if (landed[key]! > 1) return fn == 'confirm_repayment' ? null : key;
    if (fn == 'confirm_repayment') {
      final r = server.tables['loan_repayments']!.firstWhere(
        (r) => r['id'] == p['p_repayment_id'],
      )..['status'] = 'confirmed';
      final s = server.tables['loan_summaries']!.single;
      s['repaid_minor'] =
          (s['repaid_minor']! as int) + (r['amount_minor']! as int);
      s['installments_paid'] = 1;
      server.tables['needs_you']!.clear();
      return null;
    }
    return key;
  }

  SyncEngine engineWith({Duration wait = const Duration(seconds: 5)}) =>
      SyncEngine(
        db,
        server.client,
        owner: _me,
        now: () => clock,
        submitWait: wait,
      )..notices.listen(notices.add);

  /// The network goes down; writes return at once and stay queued.
  void offline() {
    server.rpc = (_, _) => _offline;
    engine.dispose();
    engine = engineWith(wait: Duration.zero);
  }

  /// The network is back, answering RPCs with [rpc]; forgets what was
  /// tried while it was down.
  Future<void> online(
    Object? Function(String, Map<String, dynamic>) rpc,
  ) async {
    await engine.sync();
    server
      ..calls.clear()
      ..rpc = rpc;
  }

  DriftLoansRepository loans() =>
      DriftLoansRepository(engine, now: () => clock);
  DriftHomeRepository home() => DriftHomeRepository(engine, now: () => clock);

  Future<Loan> loan(String id) async =>
      (await loans().load()).loans.firstWhere((l) => l.id == id);

  List<(String, Object?)> sent() => [
    for (final (fn, body) in server.calls)
      (
        fn,
        ((body['p'] as Map<String, dynamic>?) ?? body)['idempotency_key'] ??
            body['p_idempotency_key'],
      ),
  ];

  setUp(() async {
    // 10 Nov 2026, 09:00 IST.
    clock = DateTime.utc(2026, 11, 10, 3, 30);
    notices = [];
    landed = {};
    server = FakeServer();
    await server.start();
    server.tables.addAll({
      'profiles': [
        {'id': _me, 'name': 'Asha', 'phone': '+919000000001', 'upi_id': null},
        {'id': 'u-rahul', 'name': 'Rahul', 'phone': '+919000000002'},
      ],
      'space_members': [
        {
          'id': 'm9',
          'space_id': 's9',
          'user_id': _me,
          'name': null,
          'phone': '+919000000001',
          'role': 'member',
          'accepted_at': null,
          'left_at': null,
          'created_at': _at,
          'spaces': {
            'name': 'Goa trip',
            'kind': 'trip',
            'created_by': 'u-rahul',
            'deleted_at': null,
          },
        },
      ],
      'loans': [
        {
          'id': 'l1',
          'lender_id': _me,
          'borrower_id': 'u-rahul',
          'lender_phone': '+919000000001',
          'borrower_phone': '+919000000002',
          'lender_accepted_at': _at,
          'borrower_accepted_at': _at,
          'created_by': _me,
          'closed_at': null,
        },
        {
          'id': 'l2',
          'lender_id': 'u-rahul',
          'borrower_id': _me,
          'lender_phone': '+919000000002',
          'borrower_phone': '+919000000001',
          'lender_accepted_at': _at,
          'borrower_accepted_at': null,
          'created_by': 'u-rahul',
          'closed_at': null,
        },
      ],
      'loan_summaries': [
        {
          'loan_id': 'l1',
          'principal_minor': 30000,
          'repaid_minor': 0,
          'outstanding_minor': 30000,
          'installment_minor': 10000,
          'due_day': 5,
          'start_on': '2026-10-01',
          'closed_at': null,
          'installments_total': 3,
          'installments_paid': 0,
          'next_due_on': '2026-12-05',
          'ends_on': '2027-01-05',
          'on_track': false,
        },
      ],
      'loan_repayments': [
        {
          'id': 'r1',
          'loan_id': 'l1',
          'amount_minor': 10000,
          'paid_on': '2026-11-08',
          'method': 'upi',
          'reference': 'UTR1',
          'recorded_by': 'u-rahul',
          'status': 'pending',
          'dispute_reason': null,
        },
      ],
      'needs_you': [
        {
          'kind': 'repayment',
          'id': 'r1',
          'space_id': null,
          'space_name': null,
          'loan_id': 'l1',
          'counterparty': 'Rahul',
          'amount_minor': 10000,
          'paid_on': '2026-11-08',
          'created_at': '2026-11-08T10:00:00+00:00',
        },
        {
          'kind': 'settlement',
          'id': 'e7',
          'space_id': 's1',
          'space_name': 'Flat 7C',
          'loan_id': null,
          'counterparty': 'Priya',
          'amount_minor': 500,
          'paid_on': '2026-11-07',
          'created_at': '2026-11-07T10:00:00+00:00',
        },
      ],
      'rpc/activity_feed': [for (var id = 5; id > 0; id--) _activity(id)],
    });
    db = LocalDb(NativeDatabase.memory());
    engine = engineWith();
    await engine.sync();
  });

  tearDown(() async {
    final running = engine.sync();
    engine.dispose();
    await running;
    await db.close();
    await server.stop();
  });

  test('loans read from the mirror, dated in India', () async {
    clock = DateTime.utc(2026, 11, 10, 19); // Already the 11th in India.
    final data = await loans().load();
    expect(data.today, DateTime(2026, 11, 11));
    expect(data.yourName, 'Asha');
    final l = data.loans.single;
    expect(
      (l.id, l.counterparty, l.youLent, l.principal.value, l.repaid.value),
      ('l1', 'Rahul', true, 30000, 0),
    );
    expect((l.installmentsTotal, l.nextDueOn), (3, DateTime(2026, 12, 5)));
    final r = l.repayments.single;
    expect(
      (r.id, r.amount.value, r.method, r.reference, r.awaitsYou),
      ('r1', 10000, RepaymentMethod.upi, 'UTR1', true),
    );
  });

  test('a loan made offline takes a repayment; both replay in order', () async {
    offline();
    final id = await loans().createLoan(_newLoan(), idempotencyKey: 'k1');
    // create_loan makes the key the id, so nothing waits for the server.
    expect(id, 'k1');
    final repayment = await loans().recordRepayment((
      loanId: id,
      amount: const Paise(5000),
      method: RepaymentMethod.cash,
      paidOn: null,
      reference: null,
    ), idempotencyKey: 'k2');
    expect(repayment, 'k2');
    expect(await engine.unsent(), 2);

    var l = await loan('k1');
    expect(
      (l.counterparty, l.youLent, l.principal.value, l.outstanding.value),
      ('+919000000004', true, 25000, 25000),
    );
    // Three instalments from December; none due yet, so on track.
    expect(
      (l.installmentsTotal, l.installmentsPaid, l.nextDueOn, l.endsOn),
      (3, 0, DateTime(2026, 12, 5), DateTime(2027, 2, 5)),
    );
    expect((l.onTrack, l.closed), (true, false));
    final r = l.repayments.single;
    expect(
      (r.id, r.amount.value, r.status, r.recordedByYou, r.paidOn),
      ('k2', 5000, RepaymentStatus.pending, true, DateTime(2026, 11, 10)),
    );
    // Pending money never counts, and Home lists the loan already.
    expect(l.repaid.value, 0);
    expect([for (final h in (await home().load()).loans) h.id], ['l1', 'k1']);

    server.rpc = loanRpc;
    await engine.sync();
    expect(sent().sublist(sent().length - 2), [
      ('create_loan', 'k1'),
      ('record_repayment', 'k2'),
    ]);
    expect(await engine.unsent(), 0);
    expect(await db.mutations(_me), isEmpty);
    // The server's rows replaced the optimistic ones.
    l = await loan('l1');
    expect(l.repayments.single.id, 'r1');
  });

  test('a flexible loan has no schedule', () async {
    offline();
    await loans().createLoan(_newLoan(installment: null), idempotencyKey: 'k1');
    final l = await loan('k1');
    expect(
      (l.installment, l.installmentsTotal, l.nextDueOn, l.endsOn, l.onTrack),
      (null, null, null, null, null),
    );
    expect(l.outstanding.value, 25000);
  });

  test('a repayment paid earlier sorts below a newer one', () async {
    offline();
    await loans().recordRepayment((
      loanId: 'l1',
      amount: const Paise(100),
      method: null,
      paidOn: DateTime(2026, 11, 2),
      reference: 'cash',
    ), idempotencyKey: 'k1');
    final l = await loan('l1');
    expect([for (final r in l.repayments) r.id], ['r1', 'k1']);
    expect(l.repayments.last.reference, 'cash');
  });

  test('a confirmation whose response was lost counts once', () async {
    var first = true;
    server.rpc = (fn, body) {
      final result = loanRpc(fn, body);
      if (first) {
        first = false;
        return lost;
      }
      return result;
    };
    await loans().confirmRepayment('r1', idempotencyKey: 'k1');

    // It landed but the phone never heard: still queued, shown once, and
    // the mirror is not refreshed under it.
    expect(landed, {'k1': 1});
    expect(await engine.unsent(), 1);
    var l = await loan('l1');
    expect((l.repaid.value, l.outstanding.value), (10000, 20000));
    expect((l.installmentsPaid, l.onTrack), (1, true));
    expect(l.repayments.single.status, RepaymentStatus.confirmed);
    final activity = DriftActivityRepository(
      engine,
      SupabaseActivityRepository(server.client),
      now: () => clock,
    );
    expect([for (final n in await activity.needsYou()) n.id], ['e7']);

    await engine.sync();

    expect(sent(), [('confirm_repayment', 'k1'), ('confirm_repayment', 'k1')]);
    expect(server.calls.last.$2, {
      'p_repayment_id': 'r1',
      'p_idempotency_key': 'k1',
    });
    expect(await db.mutations(_me), isEmpty);
    l = await loan('l1');
    expect((l.repaid.value, l.installmentsPaid), (10000, 1));
  });

  test('the last repayment closes the loan before the server says', () async {
    server.tables['loan_summaries']!.single
      ..['repaid_minor'] = 20000
      ..['outstanding_minor'] = 10000;
    await engine.sync();
    offline();
    await loans().confirmRepayment('r1', idempotencyKey: 'k1');
    final l = await loan('l1');
    expect((l.closed, l.outstanding.value), (true, 0));
    expect((l.installmentsPaid, l.nextDueOn, l.onTrack), (3, null, null));
    expect((await home().load()).loans, isEmpty);
  });

  test('a dispute shows with its reason and never counts', () async {
    offline();
    await loans().disputeRepayment(
      'r1',
      reason: ' Not received ',
      idempotencyKey: 'k1',
    );
    final l = await loan('l1');
    final r = l.repayments.single;
    expect(
      (r.status, r.disputeReason),
      (RepaymentStatus.disputed, 'Not received'),
    );
    expect(l.repaid.value, 0);
    await engine.sync();
    expect(server.calls.first.$2, {
      'p_repayment_id': 'r1',
      'p_reason': ' Not received ',
      'p_idempotency_key': 'k1',
    });
    // Answered already, and an answer for a repayment that is gone: no-ops.
    await loans().confirmRepayment('r1', idempotencyKey: 'k2');
    await loans().confirmRepayment('nope', idempotencyKey: 'k3');
    expect((await loan('l1')).repayments.single.status, r.status);
  });

  test('a refusal after the sheet closed rolls back and says why', () async {
    offline();
    await loans().recordRepayment((
      loanId: 'l1',
      amount: const Paise(99000),
      method: null,
      paidOn: null,
      reference: null,
    ), idempotencyKey: 'k1');
    expect((await loan('l1')).repayments, hasLength(2));

    await online((_, _) => const Refuse('22023', hint: 'overpayment'));
    await engine.sync();

    expect(await db.mutations(_me), isEmpty);
    expect((await loan('l1')).repayments.single.id, 'r1');
    await pumpEventQueue();
    expect(
      notices.single,
      'Your repayment of ₹990 couldn’t be saved because it is more than is '
      'left on the loan. We’ve undone it on this phone.',
    );
  });

  group('a refusal while the sheet waits is thrown and rolled back', () {
    for (final (name, refuse, matcher) in [
      (
        'overpayment',
        const Refuse('22023', hint: 'overpayment'),
        isA<LoanRejected>().having(
          (e) => e.reason,
          'reason',
          LoanRejection.overpayment,
        ),
      ),
      (
        'not a party',
        const Refuse('42501'),
        isA<LoanRejected>().having(
          (e) => e.reason,
          'reason',
          LoanRejection.notAllowed,
        ),
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
          loans().confirmRepayment('r1', idempotencyKey: 'k1'),
          throwsA(matcher),
        );
        expect(await db.mutations(_me), isEmpty);
        expect((await loan('l1')).repaid.value, 0);
        await pumpEventQueue();
        expect(notices, isEmpty);
      });
    }

    test('a claim someone else answered', () async {
      server.rpc = (_, _) => const Refuse('42501');
      await expectLater(
        home().acceptClaim(_spaceClaim, idempotencyKey: 'k1'),
        throwsA(isA<PostgrestException>()),
      );
      expect((await home().load()).claims, hasLength(2));
    });
  });

  test('claims answered offline show at once and replay with keys', () async {
    expect(
      [for (final c in (await home().load()).claims) (c.kind, c.id)],
      [(ClaimKind.spaceMember, 'm9'), (ClaimKind.loan, 'l2')],
    );
    offline();
    await home().acceptClaim(_spaceClaim, idempotencyKey: 'k1');
    await home().rejectClaim(_loanClaim, idempotencyKey: 'k2');

    final h = await home().load();
    expect(h.claims, isEmpty);
    expect([for (final s in h.spaces) s.name], ['Goa trip']);
    expect([for (final l in h.loans) l.id], ['l1']);
    expect([for (final l in (await loans().load()).loans) l.id], ['l1']);

    await online((_, _) => null);
    await engine.sync();
    expect(
      [for (final (fn, _) in server.calls) fn],
      ['accept_claim', 'reject_claim'],
    );
    expect(
      [for (final (_, body) in server.calls) body],
      [
        {'p_kind': 'space_member', 'p_id': 'm9', 'p_idempotency_key': 'k1'},
        {'p_kind': 'loan', 'p_id': 'l2', 'p_idempotency_key': 'k2'},
      ],
    );
    expect(await engine.unsent(), 0);
  });

  test('the other answers: a loan accepted, a space declined', () async {
    offline();
    await home().acceptClaim(_loanClaim, idempotencyKey: 'k1');
    await home().rejectClaim(_spaceClaim, idempotencyKey: 'k2');
    // A second answer to either changes nothing more.
    await home().rejectClaim(_loanClaim, idempotencyKey: 'k3');
    await home().acceptClaim(_spaceClaim, idempotencyKey: 'k4');
    await home().acceptClaim(
      const Claim(
        kind: ClaimKind.loan,
        id: 'gone',
        title: '',
        recordedBy: '',
        amount: Paise.zero,
      ),
      idempotencyKey: 'k5',
    );
    final h = await home().load();
    expect(h.claims, isEmpty);
    expect(h.spaces, isEmpty);
    expect(
      [for (final l in h.loans) (l.id, l.youLent)],
      [('l1', true), ('l2', false)],
    );
  });

  test('an accept whose response was lost is replayed, not refused', () async {
    var first = true;
    server.rpc = (_, _) {
      if (!first) return null;
      first = false;
      return lost;
    };
    await home().acceptClaim(_spaceClaim, idempotencyKey: 'k1');
    expect(await engine.unsent(), 1);
    expect((await home().load()).spaces.single.name, 'Goa trip');

    await engine.sync();
    expect(sent(), [('accept_claim', 'k1'), ('accept_claim', 'k1')]);
    expect(await engine.unsent(), 0);
    await pumpEventQueue();
    expect(notices, isEmpty);
  });

  test('an answer first sent 31 days ago is dropped and undone', () async {
    for (final answer in [
      () => home().acceptClaim(_spaceClaim, idempotencyKey: 'k1'),
      () => loans().confirmRepayment('r1', idempotencyKey: 'k2'),
    ]) {
      offline();
      await answer();
      await online((_, _) => null);
      clock = clock.add(const Duration(days: 31));
      await engine.sync();

      // The server may have forgotten the key: it is not sent again.
      expect(server.calls, isEmpty);
      expect(await db.mutations(_me), isEmpty);
    }
    expect((await home().load()).claims, hasLength(2));
    expect((await loan('l1')).repaid.value, 0);
    await pumpEventQueue();
    String late(String what) =>
        '$what couldn’t be saved because it waited too long to reach the '
        'server. We’ve undone it on this phone.';
    expect(notices, [
      late('Accepting that invite'),
      late('Your confirmation of that repayment'),
    ]);
  });

  test('every refused loan or claim write has plain copy', () {
    Mutation m(String kind, Map<String, dynamic> params) => (
      id: 1,
      key: 'k',
      kind: kind,
      params: params,
      createdAt: clock,
      firstAttemptAt: null,
      attempts: 0,
      applied: false,
    );
    String says(String kind, String code, [String? hint]) => rejection(
      m(kind, {
        'p': {'principal_minor': 250000, 'amount_minor': 5000},
      }),
      PostgrestException(message: '', code: code, hint: hint),
    ).replaceFirst(' We’ve undone it on this phone.', '');
    for (final (said, what, why) in [
      (
        says('create_loan', '22023'),
        'Your loan of ₹2,500',
        'the details didn’t match the loan',
      ),
      (
        says('record_repayment', '22023', 'loan_closed'),
        'Your repayment of ₹50',
        'the loan is already fully repaid',
      ),
      (
        says('confirm_repayment', '22023', 'not_pending'),
        'Your confirmation of that repayment',
        'the repayment was already answered',
      ),
      (
        says('dispute_repayment', '42501', 'own_record'),
        'Your dispute of that repayment',
        'you can’t change this loan any more',
      ),
      (
        says('accept_claim', '42501'),
        'Accepting that invite',
        'it was already answered or withdrawn',
      ),
      (
        says('reject_claim', '42501'),
        'Declining that invite',
        'it was already answered or withdrawn',
      ),
      (
        says('question_activity', '42501'),
        'Your question about that edit',
        'you can’t question that edit any more',
      ),
    ]) {
      expect(said, '$what couldn’t be saved because $why.');
    }
  });

  test('answering a settle-up or deleting it clears what waits', () async {
    final activity = DriftActivityRepository(
      engine,
      SupabaseActivityRepository(server.client),
      now: () => clock,
    );
    final waiting = await activity.needsYou();
    expect(
      [for (final n in waiting) (n.id, n.isRepayment, n.counterparty)],
      [('r1', true, 'Rahul'), ('e7', false, 'Priya')],
    );
    offline();
    await DriftSpaceLedgerRepository(engine)
        .disputeSettlement('e7', 'No', idempotencyKey: 'k1');
    expect([for (final n in await activity.needsYou()) n.id], ['r1']);
    await DriftSpaceLedgerRepository(engine)
        .deleteExpense('r1', idempotencyKey: 'k2');
    expect(await activity.needsYou(), isEmpty);
  });

  group('the activity feed', () {
    late DriftActivityRepository activity;
    setUp(
      () => activity = DriftActivityRepository(
        engine,
        SupabaseActivityRepository(server.client),
        now: () => clock,
      ),
    );

    test('pages through the mirror by cursor, offline', () async {
      server
        ..readStatus = 503
        ..rpc = (_, _) => _offline;
      final first = await activity.feed(limit: 2);
      expect([for (final e in first) e.id], [5, 4]);
      final second = await activity.feed(limit: 2, before: first.last);
      expect([for (final e in second) e.id], [3, 2]);
      final third = await activity.feed(limit: 2, before: second.last);
      expect([for (final e in third) e.id], [1]);
      // The mirror held the whole feed: nothing asked the server.
      expect(server.calls, isEmpty);
    });

    test('asks the server for pages older than the mirror keeps', () async {
      server.tables['rpc/activity_feed'] = [
        for (var id = 200; id > 200 - mirroredActivity; id--)
          {..._activity(id), 'created_at': '2026-11-02T00:00:00+00:00'},
      ];
      await engine.sync();
      expect(server.reads, contains('rpc/activity_feed'));
      final top = await activity.feed(limit: 30);
      expect((top.first.id, top.last.id), (200, 171));
      expect(server.calls, isEmpty);

      final last = (await activity.feed(limit: 100)).last;
      server.rpc = (fn, body) => [_activity(7)];
      final older = await activity.feed(limit: 30, before: last);
      expect([for (final e in older) e.id], [7]);
      expect(server.calls.single.$1, 'activity_feed');
      expect(server.calls.single.$2, {
        'p_limit': 30,
        'p_before_at': '2026-11-02T00:00:00.000Z',
        'p_before_id': 101,
      });

      // Offline, the feed ends where the mirror does.
      offline();
      expect(await activity.feed(limit: 30, before: last), isEmpty);
    });
  });

  group('activity filters, unread and questions (#109)', () {
    // Made when used: going offline replaces the engine.
    DriftActivityRepository activity() => DriftActivityRepository(
      engine,
      SupabaseActivityRepository(server.client),
      now: () => clock,
    );

    // Someone else's row on [day] of November: even ids in space s1, odd
    // ids on loan l1.
    Map<String, Object?> row(int id, {int day = 1, bool byMe = false}) => {
      ..._activity(id),
      'created_at': '2026-11-${'$day'.padLeft(2, '0')}T00:00:00+00:00',
      'by_me': byMe,
      if (id.isEven) 'space_id': 's1' else 'loan_id': 'l1',
      if (id.isOdd) 'kind': 'loan',
    };
    const flat = (spaceId: 's1', loansOnly: false);
    const loansOnly = (spaceId: null, loansOnly: true);

    test('filters the mirror offline, by the same cursor', () async {
      server.tables['rpc/activity_feed'] = [
        for (var id = 6; id > 0; id--) row(id),
      ];
      await engine.sync();
      server
        ..readStatus = 503
        ..calls.clear()
        ..rpc = (_, _) => _offline;

      final first = await activity().feed(limit: 2, filter: flat);
      expect([for (final e in first) e.id], [6, 4]);
      final second = await activity().feed(
        limit: 2,
        before: first.last,
        filter: flat,
      );
      expect([for (final e in second) e.id], [2]);
      expect(
        [
          for (final e in await activity().feed(limit: 9, filter: loansOnly))
            e.id,
        ],
        [5, 3, 1],
      );
      // The mirror held the whole feed: nothing asked the server.
      expect(server.calls, isEmpty);
    });

    test(
      'asks the server, with the filter, past what the mirror keeps',
      () async {
        server.tables['rpc/activity_feed'] = [
          for (var id = 200; id > 200 - mirroredActivity; id--)
            {...row(id), 'loan_id': null, 'kind': 'expense'},
        ];
        await engine.sync();
        server.calls.clear();

        // The newest 30 of the mirror's 50 Flat rows make a page by themselves.
        final top = await activity().feed(limit: 30, filter: flat);
        expect((top.first.id, top.last.id), (200, 142));
        expect(server.calls, isEmpty);

        // 20 are left, so the server is asked for the page, filter and all.
        server.rpc = (fn, body) => [row(8)];
        final older = await activity().feed(
          limit: 30,
          before: top.last,
          filter: flat,
        );
        expect([for (final e in older) e.id], [8]);
        expect(server.calls.single.$1, 'activity_feed');
        expect(server.calls.single.$2, {
          'p_limit': 30,
          'p_space_id': 's1',
          'p_before_at': '2026-11-01T00:00:00.000Z',
          'p_before_id': 142,
        });

        // A full mirror with no loan rows cannot say there are none.
        server
          ..calls.clear()
          ..rpc = (fn, body) => [row(7)];
        final loanRows = await activity().feed(limit: 30, filter: loansOnly);
        expect([for (final e in loanRows) e.id], [7]);
        expect(server.calls.single.$2, {'p_limit': 30, 'p_loans_only': true});

        // Offline, a filtered feed ends where the mirror does.
        offline();
        final rest = await activity().feed(
          limit: 30,
          before: top.last,
          filter: flat,
        );
        expect((rest.length, rest.first.id, rest.last.id), (20, 140, 102));
      },
    );

    test('unread counts from the mirror; seeing it works offline and '
        'reaches the server later', () async {
      server
        ..tables['rpc/activity_feed'] = [
          row(4, day: 4, byMe: true),
          row(3, day: 3),
          row(2, day: 2),
          row(1),
        ]
        ..tables['activity_seen'] = [
          {'seen_at': '2026-11-01T12:00:00+00:00'},
        ];
      await engine.sync();
      // Yours never counts, nor what you saw.
      expect(await activity().unread(), 2);

      offline();
      await activity().markSeen();
      expect(await activity().unread(), 0);
      // Nothing of the user's is unsent, so signing out does not ask.
      expect(await engine.unsent(), 0);
      // Seeing the same feed again queues nothing more.
      await activity().markSeen();
      expect(await db.mutations(_me), hasLength(1));

      await online((fn, body) {
        server.tables['activity_seen'] = [
          {'seen_at': body['p_at']},
        ];
        return null;
      });
      await engine.sync();
      expect(server.calls.single.$1, 'mark_activity_seen');
      expect(server.calls.single.$2, {'p_at': '2026-11-04T00:00:00.000Z'});
      expect(await db.mutations(_me), isEmpty);
      expect(await activity().unread(), 0);

      // The count follows the server's cursor once it is mirrored.
      server.tables['activity_seen'] = [
        {'seen_at': '2026-11-02T12:00:00+00:00'},
      ];
      await engine.sync();
      expect(await activity().unread(), 1);
    });

    test('before anything was seen, all of the mirror counts; a refused '
        "'seen' is dropped without a word", () async {
      server.tables['rpc/activity_feed'] = [row(2, day: 2), row(1)];
      await engine.sync();
      expect(await activity().unread(), 2);

      offline();
      await activity().markSeen();
      await online((_, _) => const Refuse('42501'));
      await engine.sync();
      await pumpEventQueue();
      expect(await db.mutations(_me), isEmpty);
      expect(notices, isEmpty);
      expect(await activity().unread(), 2);

      // With nothing in the feed there is nothing to see.
      server
        ..calls.clear()
        ..tables['rpc/activity_feed'] = [];
      await engine.sync();
      await activity().markSeen();
      expect(server.calls, isEmpty);
    });

    test('a question asked offline shows on its row, redacted, and '
        'replays', () async {
      server.tables['rpc/activity_feed'] = [
        {
          ...row(2),
          'action': 'edited',
          'questions': [
            {'by_me': false, 'name': 'Priya', 'note': 'Call ९८००० ००००९?'},
          ],
        },
        row(1),
      ];
      await engine.sync();
      final [edit, _] = await activity().feed(limit: 9);
      // Whatever the server stored, a number is never shown.
      expect(edit.questions.single, (
        byYou: false,
        name: 'Priya',
        note: 'Call ••••?',
      ));
      expect(edit.canQuestion, isTrue);

      offline();
      await activity().question(edit, '  Why? Ask 98000 00009  ');
      final [asked, other] = await activity().feed(limit: 9);
      expect(asked.questions, [
        (byYou: false, name: 'Priya', note: 'Call ••••?'),
        (byYou: true, name: null, note: 'Why? Ask ••••'),
      ]);
      expect(asked.canQuestion, isFalse);
      expect(other.questions, isEmpty);

      await online((_, _) => null);
      await engine.sync();
      expect(server.calls.single.$1, 'question_activity');
      expect(server.calls.single.$2, {
        'p_activity_id': 2,
        'p_note': 'Why? Ask ••••',
      });
    });

    test(
      'a question about a row the mirror no longer has changes nothing',
      () async {
        offline();
        await activity().question(
          activityFromRows([
            {..._activity(99), 'action': 'edited', 'by_me': false},
          ]).single,
          'Why?',
        );
        expect([
          for (final e in await activity().feed(limit: 9)) e.questions,
        ], everyElement(isEmpty));
      },
    );
  });

  group('a read cut at max_rows', () {
    Map<String, Object?> expense(String id, String space, String on) => {
      'id': id,
      'space_id': space,
      'spent_on': on,
      'created_at': on,
    };

    test('is read again space by space, a page at a time', () async {
      server
        ..maxRows = 2
        ..tables['spaces'] = [
          {'id': 's1'},
          {'id': 's2'},
          {'id': 's3'},
        ]
        ..tables['expenses'] = [
          expense('e5', 's1', '2026-11-09'),
          expense('e4', 's2', '2026-11-08'),
          expense('e3', 's1', '2026-11-07'),
          expense('e2', 's1', '2026-11-07'),
          expense('e1', 's2', '2026-11-01'),
        ]
        ..reads.clear();
      final t = await fetchMirror(server.client, clock, pageSize: 2);

      // Every expense, in the order one uncapped read gives.
      expect(
        [for (final e in t['expenses']!) e['id']],
        ['e5', 'e4', 'e2', 'e3', 'e1'],
      );
      expect(
        server.reads.where((r) => r.startsWith('expenses')),
        unorderedEquals([
          'expenses',
          'expenses space_id=s1 offset=0',
          'expenses space_id=s1 offset=2',
          'expenses space_id=s2 offset=0',
          'expenses space_id=s2 offset=2',
          'expenses space_id=s3 offset=0',
        ]),
      );
      expect(server.reads.where((r) => r.startsWith('spaces')), [
        'spaces offset=0',
        'spaces offset=2',
      ]);
      // Loans have no space: paged from where the first read stopped.
      expect([for (final l in t['loans']!) l['id']], ['l1', 'l2']);
      expect(server.reads.where((r) => r.startsWith('loans')), [
        'loans',
        'loans offset=2',
      ]);
      // A short read is the whole table: one request.
      expect(server.reads.where((r) => r.startsWith('loan_summaries')), [
        'loan_summaries',
      ]);
    });

    test('through the engine, with its page size', () async {
      server
        ..maxRows = 1
        ..tables['spaces'] = [];
      engine.dispose();
      engine = SyncEngine(
        db,
        server.client,
        owner: _me,
        now: () => clock,
        pageSize: 1,
      );
      await engine.sync();
      expect((await loans().load()).loans.single.id, 'l1');
      expect((await db.mirror(_me))['loans'], hasLength(2));
    });
  });

  test('a v2 store upgrades: the mirror refetches, the queue stays', () async {
    final v2 = LocalDb(
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
            "status TEXT NOT NULL DEFAULT 'pending', "
            'first_attempt_at INTEGER)',
          )
          ..execute(
            'CREATE TABLE local_ids (owner TEXT NOT NULL, '
            'local_id TEXT NOT NULL, server_id TEXT NOT NULL, '
            'PRIMARY KEY (owner, local_id))',
          )
          ..execute(
            "INSERT INTO mirror VALUES ('$_me', 'loan_summaries', "
            """'[{"loan_id":"l1"}]')""",
          )
          ..execute(
            'INSERT INTO pending_mutations '
            '(owner, idempotency_key, kind, payload, created_at, status) '
            "VALUES ('$_me', 'k1', 'delete_expense', '{}', 1000, 'pending'), "
            "('$_me', 'k2', 'delete_expense', '{}', 2000, 'applied')",
          )
          ..execute('PRAGMA user_version = 2'),
      ),
    );
    addTearDown(v2.close);
    // v2 summaries lack the columns loans read; they are refetched.
    expect(await v2.mirror(_me), isEmpty);
    expect([for (final m in await v2.mutations(_me)) m.key], ['k1', 'k2']);
    // Only what the server has not accepted is unsent.
    expect(await v2.unsent(_me), 1);
    expect(await v2.unsent('u-else'), 0);
  });
}
