import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:settlo_core/settlo_core.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

const _me = 'u-me';

Map<String, Object?> _summary(String id, {required int repaid}) => {
  'loan_id': id,
  'principal_minor': 100000000,
  'repaid_minor': repaid,
  'installment_minor': 2500000,
  'due_day': 5,
  'start_on': '2026-03-05',
  'closed_at': null,
  'installments_total': 40,
  'installments_paid': repaid ~/ 2500000,
  'next_due_on': '2026-12-05',
  'ends_on': '2029-07-05',
  'on_track': true,
};

/// Rows as PostgREST returns them to a party under RLS.
final _tables = <String, List<Map<String, Object?>>>{
  'loans': [
    // You lent Arjun ₹10 lakh.
    {
      'id': 'l1',
      'lender_id': _me,
      'borrower_id': 'u-arjun',
      'lender_phone': '+919876543210',
      'borrower_phone': '+919800000002',
      'lender_accepted_at': '2026-03-05T10:00:00Z',
      'borrower_accepted_at': '2026-03-05T11:00:00Z',
    },
    // Recorded against you, not yet accepted: Home shows it as a claim.
    {
      'id': 'l2',
      'lender_id': 'u-meera',
      'borrower_id': _me,
      'lender_phone': '+919800000003',
      'borrower_phone': '+919876543210',
      'lender_accepted_at': '2026-11-01T10:00:00Z',
      'borrower_accepted_at': null,
    },
    // Fully repaid, and flexible.
    {
      'id': 'l3',
      'lender_id': 'u-dev',
      'borrower_id': _me,
      'lender_phone': '+919800000004',
      'borrower_phone': '+919876543210',
      'lender_accepted_at': '2026-01-01T10:00:00Z',
      'borrower_accepted_at': '2026-01-01T10:00:00Z',
    },
    // You borrowed from a number that has not joined.
    {
      'id': 'l4',
      'lender_id': null,
      'borrower_id': _me,
      'lender_phone': '+919800000005',
      'borrower_phone': '+919876543210',
      'lender_accepted_at': null,
      'borrower_accepted_at': '2026-11-02T10:00:00Z',
    },
  ],
  'loan_summaries': [
    _summary('l1', repaid: 32500000),
    _summary('l2', repaid: 0),
    {
      'loan_id': 'l3',
      'principal_minor': 500000,
      'repaid_minor': 500000,
      'installment_minor': null,
      'due_day': null,
      'start_on': '2026-01-01',
      'closed_at': '2026-06-01T10:00:00Z',
      'installments_total': null,
      'installments_paid': null,
      'next_due_on': null,
      'ends_on': null,
      'on_track': null,
    },
    _summary('l4', repaid: 0),
  ],
  'loan_repayments': [
    {
      'id': 'r2',
      'loan_id': 'l1',
      'amount_minor': 2500000,
      'paid_on': '2026-11-05',
      'method': 'upi',
      'reference': 'UPI 4321',
      'recorded_by': 'u-arjun',
      'status': 'pending',
      'dispute_reason': null,
    },
    {
      'id': 'r1',
      'loan_id': 'l1',
      'amount_minor': 2500000,
      'paid_on': '2026-10-05',
      'method': null,
      'reference': null,
      'recorded_by': _me,
      'status': 'disputed',
      'dispute_reason': 'Not received yet',
    },
  ],
  'profiles': [
    {'id': _me, 'name': 'Sana'},
    {'id': 'u-arjun', 'name': 'Arjun'},
    {'id': 'u-dev', 'name': 'Dev'},
  ],
};

void main() {
  late HttpServer server;
  late SupabaseClient client;
  late List<String> requests;

  /// The error the server answers a body containing the key with.
  const errors = <String, (int, String, String?)>{
    'k-conflict': (409, 'PT409', 'idempotency_conflict'),
    'k-over': (400, '22023', 'overpayment'),
    'k-closed': (400, '22023', 'loan_closed'),
    'k-answered': (400, '22023', 'not_pending'),
    'k-own': (403, '42501', 'own_record'),
    'k-outsider': (403, '42501', null),
    'k-reason': (400, '22023', null),
    'k-interest': (400, '22023', 'interest_not_supported'),
    'k-other': (500, 'XX000', null),
  };

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
        final error = errors.entries
            .where((e) => body.contains(e.key))
            .firstOrNull
            ?.value;
        request.response.headers.contentType = ContentType.json;
        if (error case (final status, final code, final hint)) {
          request.response
            ..statusCode = status
            ..write(
              jsonEncode({'code': code, 'message': 'refused', 'hint': hint}),
            );
        } else if (path == 'rpc/record_repayment') {
          request.response.write(jsonEncode('k-record'));
        } else if (path == 'rpc/create_loan') {
          request.response.write(jsonEncode('k-create'));
        } else if (path.startsWith('rpc/')) {
          request.response.statusCode = 204;
        } else {
          request.response.write(jsonEncode(_tables[path]));
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

  LoansRepository repository() => SupabaseLoansRepository(
    client,
    userId: _me,
    // 20:00 UTC is already the next day in India.
    now: () => DateTime.utc(2026, 11, 8, 20),
  );

  test('loads accepted loans with their repayments, open first', () async {
    final data = await repository().load();

    expect(data.today, DateTime(2026, 11, 9));
    expect(data.yourName, 'Sana');
    expect([for (final l in data.loans) l.id], ['l1', 'l4', 'l3']);

    final arjun = data.loans.first;
    expect(
      (arjun.counterparty, arjun.youLent, arjun.closed),
      ('Arjun', true, false),
    );
    expect(
      (arjun.principal, arjun.repaid, arjun.outstanding),
      (
        const Paise.rupees(1000000),
        const Paise.rupees(325000),
        const Paise.rupees(675000),
      ),
    );
    expect(arjun.progress, 0.325);
    expect(
      (arjun.installment, arjun.dueDay, arjun.installmentsPaid),
      (const Paise.rupees(25000), 5, 13),
    );
    expect(
      (arjun.startOn, arjun.nextDueOn, arjun.endsOn, arjun.onTrack),
      (DateTime(2026, 3, 5), DateTime(2026, 12, 5), DateTime(2029, 7, 5), true),
    );

    final [pending, disputed] = arjun.repayments;
    expect(
      (pending.status, pending.method, pending.reference, pending.awaitsYou),
      (RepaymentStatus.pending, RepaymentMethod.upi, 'UPI 4321', true),
    );
    expect(
      (disputed.status, disputed.method, disputed.disputeReason),
      (RepaymentStatus.disputed, null, 'Not received yet'),
    );
    expect((disputed.recordedByYou, disputed.awaitsYou), (true, false));
    expect(arjun.awaitsYou, isTrue);

    // A number that has not joined shows as itself.
    expect(data.loans[1].counterparty, '+919800000005');

    final dev = data.loans.last;
    expect((dev.counterparty, dev.youLent, dev.closed), ('Dev', false, true));
    expect((dev.installment, dev.dueDay, dev.onTrack), (null, null, null));
    expect(dev.progress, 1);
    expect(dev.repayments, isEmpty);
  });

  group('createLoan', () {
    NewLoan loan({Paise? installment, int? dueDay}) => (
      youLent: true,
      counterpartyPhone: '+919800000002',
      principal: const Paise.rupees(1000000),
      installment: installment,
      dueDay: dueDay,
      startOn: DateTime(2026, 11, 10),
    );

    test('sends a monthly loan with its key and returns the id', () async {
      final id = await repository().createLoan(
        loan(installment: const Paise.rupees(25000), dueDay: 5),
        idempotencyKey: '3e7a0000-0000-4000-8000-000000000001',
      );

      expect(id, 'k-create');
      final body = jsonEncode({
        'p': {
          'idempotency_key': '3e7a0000-0000-4000-8000-000000000001',
          'direction': 'lent',
          'counterparty_phone': '+919800000002',
          'principal_minor': 100000000,
          'installment_minor': 2500000,
          'due_day': 5,
          'start_on': '2026-11-10',
        },
      });
      expect(requests, ['POST rpc/create_loan  $body']);
    });

    test(
      'a flexible loan sends no schedule; borrowed is the other side',
      () async {
        await repository().createLoan((
          youLent: false,
          counterpartyPhone: '+919800000002',
          principal: const Paise(500),
          installment: null,
          dueDay: null,
          startOn: DateTime(2026),
        ), idempotencyKey: 'k1');
        final p = (jsonDecode(requests.single.split('  ').last) as Map)['p'];
        expect(p, {
          'idempotency_key': 'k1',
          'direction': 'borrowed',
          'counterparty_phone': '+919800000002',
          'principal_minor': 500,
          'start_on': '2026-01-01',
        });
      },
    );

    test('refusals and conflicts map as for repayments', () async {
      await expectLater(
        repository().createLoan(loan(), idempotencyKey: 'k-interest'),
        throwsA(
          isA<LoanRejected>().having(
            (e) => e.reason,
            'reason',
            LoanRejection.invalid,
          ),
        ),
      );
      await expectLater(
        repository().createLoan(loan(), idempotencyKey: 'k-conflict'),
        throwsA(isA<IdempotencyConflict>()),
      );
    });
  });

  test('records a repayment with its key and returns the id', () async {
    final id = await repository().recordRepayment((
      loanId: 'l1',
      amount: const Paise.rupees(25000),
      method: RepaymentMethod.cash,
      reference: null,
    ), idempotencyKey: '7b1c0000-0000-4000-8000-000000000001');

    expect(id, 'k-record');
    final body = jsonEncode({
      'p': {
        'loan_id': 'l1',
        'idempotency_key': '7b1c0000-0000-4000-8000-000000000001',
        'amount_minor': 2500000,
        'method': 'cash',
      },
    });
    expect(requests, ['POST rpc/record_repayment  $body']);
  });

  test('confirms and disputes with their keys', () async {
    await repository().confirmRepayment('r2', idempotencyKey: 'c2d4');
    await repository().disputeRepayment(
      'r2',
      reason: 'Not received yet',
      idempotencyKey: 'e5f6',
    );

    final confirm = {'p_repayment_id': 'r2', 'p_idempotency_key': 'c2d4'};
    final dispute = {
      'p_repayment_id': 'r2',
      'p_reason': 'Not received yet',
      'p_idempotency_key': 'e5f6',
    };
    expect(requests, [
      'POST rpc/confirm_repayment  ${jsonEncode(confirm)}',
      'POST rpc/dispute_repayment  ${jsonEncode(dispute)}',
    ]);
  });

  group('refusals become plain copy', () {
    for (final (key, reason, copy) in [
      (
        'k-over',
        LoanRejection.overpayment,
        "That's more than is left on the loan. Check the amount.",
      ),
      (
        'k-closed',
        LoanRejection.closed,
        'This loan is fully repaid. Nothing more to record.',
      ),
      (
        'k-answered',
        LoanRejection.notPending,
        'This repayment was already answered. Pull down to see it.',
      ),
      (
        'k-own',
        LoanRejection.ownRecord,
        'Your side recorded this one, so the other person confirms it.',
      ),
      ('k-outsider', LoanRejection.notAllowed, "You can't change this loan."),
      (
        'k-reason',
        LoanRejection.invalid,
        "That didn't go through. Check it and try again.",
      ),
    ]) {
      test(reason.name, () async {
        await expectLater(
          repository().confirmRepayment('r2', idempotencyKey: key),
          throwsA(
            isA<LoanRejected>()
                .having((e) => e.reason, 'reason', reason)
                .having((e) => e.message, 'message', copy)
                .having((e) => '$e', 'toString', isNot(contains('22023'))),
          ),
        );
      });
    }

    test('a key reused with another payload is a conflict', () async {
      await expectLater(
        repository().recordRepayment((
          loanId: 'l1',
          amount: const Paise(100),
          method: null,
          reference: null,
        ), idempotencyKey: 'k-conflict'),
        throwsA(isA<IdempotencyConflict>()),
      );
    });

    test('anything else is rethrown', () async {
      await expectLater(
        repository().disputeRepayment(
          'r2',
          reason: 'x',
          idempotencyKey: 'k-other',
        ),
        throwsA(isA<PostgrestException>()),
      );
    });
  });
}
