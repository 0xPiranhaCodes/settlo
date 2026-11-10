import 'dart:convert';
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:settlo_core/settlo_core.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

const _me = 'u-me';
const _at = '2026-11-01T10:00:00Z';

Map<String, Object?> _member(
  String id,
  String space, {
  String? user,
  String? name,
  String phone = '+919000000000',
  bool accepted = true,
  bool left = false,
}) => {
  'id': id,
  'space_id': space,
  'user_id': user,
  'name': name,
  'phone': phone,
  'accepted_at': user != null && accepted ? _at : null,
  'left_at': left ? _at : null,
  'spaces': _spaces[space],
};

const _spaces = <String, Map<String, String?>>{
  's1': {
    'name': 'Flat 402',
    'kind': 'flat',
    'created_by': _me,
    'deleted_at': null,
  },
  's2': {
    'name': 'Goa trip',
    'kind': 'trip',
    'created_by': _me,
    'deleted_at': null,
  },
  's3': {
    'name': 'Old flat',
    'kind': 'flat',
    'created_by': _me,
    'deleted_at': _at,
  },
  's4': {
    'name': 'Flat 9',
    'kind': 'flat',
    'created_by': 'u-rahul',
    'deleted_at': null,
  },
  's5': {
    'name': 'Left',
    'kind': 'other',
    'created_by': _me,
    'deleted_at': null,
  },
};

/// Rows as PostgREST returns them to the signed-in user under RLS.
final _tables = <String, List<Map<String, Object?>>>{
  'space_members': [
    _member('m1', 's1', user: _me),
    _member('m2', 's1', user: 'u-rahul'),
    _member('m3', 's1', name: 'Priya'),
    _member('m4', 's1', name: 'Gone', left: true),
    _member('m5', 's2', user: _me),
    _member('m6', 's2', phone: '+919000000006'),
    _member('m7', 's3', user: _me),
    _member('m8', 's4', user: _me, accepted: false),
    _member('m9', 's4', user: 'u-rahul'),
    _member('m10', 's5', user: _me, left: true),
  ],
  'space_member_balances': [
    {'member_id': 'm1', 'balance_minor': 285000},
    {'member_id': 'm5', 'balance_minor': -365000},
    {'member_id': 'm8', 'balance_minor': -75000},
  ],
  'space_monthly_fairness': [
    {'member_id': 'm1', 'fair_share_minor': 1200000},
    {'member_id': 'm5', 'fair_share_minor': 645000},
    {'member_id': 'm8', 'fair_share_minor': 99900},
  ],
  'loans': [
    {
      'id': 'l1',
      'lender_id': _me,
      'borrower_id': 'u-arjun',
      'lender_phone': '+919876543210',
      'borrower_phone': '+919100000003',
      'lender_accepted_at': _at,
      'borrower_accepted_at': _at,
      'created_by': _me,
      'closed_at': null,
    },
    {
      'id': 'l2',
      'lender_id': _me,
      'borrower_id': null,
      'lender_phone': '+919876543210',
      'borrower_phone': '+919100000004',
      'lender_accepted_at': null,
      'borrower_accepted_at': _at,
      'created_by': 'u-kabir',
      'closed_at': null,
    },
    {
      'id': 'l3',
      'lender_id': 'u-arjun',
      'borrower_id': _me,
      'lender_phone': '+919100000003',
      'borrower_phone': '+919876543210',
      'lender_accepted_at': _at,
      'borrower_accepted_at': _at,
      'created_by': _me,
      'closed_at': _at,
    },
  ],
  'loan_summaries': [
    {
      'loan_id': 'l1',
      'principal_minor': 100000000,
      'outstanding_minor': 67500000,
      'installment_minor': 2500000,
      'installments_total': 40,
      'installments_paid': 13,
      'next_due_on': '2026-12-05',
    },
    {
      'loan_id': 'l2',
      'principal_minor': 50000000,
      'outstanding_minor': 50000000,
      'installment_minor': null,
      'installments_total': null,
      'installments_paid': null,
      'next_due_on': null,
    },
  ],
  'loan_repayments': [
    {
      'id': 'r1',
      'loan_id': 'l1',
      'amount_minor': 2500000,
      'recorded_by': 'u-arjun',
      'status': 'pending',
    },
  ],
  'profiles': [
    {'id': _me, 'name': 'Sana', 'phone': '+919876543210'},
    {'id': 'u-rahul', 'name': 'Rahul', 'phone': '+919100000001'},
    {'id': 'u-arjun', 'name': 'Arjun', 'phone': '+919100000003'},
    {'id': 'u-kabir', 'name': 'Kabir', 'phone': '+919100000004'},
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
        final query = request.uri.query;
        requests.add(
          '${request.method} $path $query${body.isEmpty ? '' : ' $body'}',
        );
        request.response
          ..headers.contentType = ContentType.json
          ..write(path.startsWith('rpc/') ? 'null' : jsonEncode(_tables[path]));
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

  HomeRepository repository() => SupabaseHomeRepository(
    client,
    userId: _me,
    now: () => DateTime(2026, 11, 9, 23, 59),
  );

  test('joins the views into accepted spaces, loans and claims', () async {
    final home = await repository().load();

    expect(home.phone, '+919876543210');
    expect(home.name, 'Sana');
    expect(home.month, DateTime(2026, 11));
    expect(
      requests,
      contains(
        startsWith(
          'GET space_monthly_fairness '
          'select=member_id%2Cfair_share_minor&month=eq.2026-11-01',
        ),
      ),
    );

    // Deleted spaces and spaces you left are gone; labels fall back from
    // the creator's label to the profile name to the number.
    expect(
      [
        for (final s in home.spaces)
          (s.id, s.name, s.kind, s.balance.value, s.people.join(', ')),
      ],
      [
        ('s1', 'Flat 402', SpaceKind.flat, 285000, 'Rahul, Priya'),
        ('s2', 'Goa trip', SpaceKind.trip, -365000, '+919000000006'),
      ],
    );

    final loan = home.loans.single;
    expect(
      (loan.id, loan.counterparty, loan.youLent, loan.balance.value),
      ('l1', 'Arjun', true, 67500000),
    );
    expect(
      (
        loan.installment?.value,
        loan.installmentsPaid,
        loan.installmentsTotal,
        loan.nextDueOn,
      ),
      (2500000, 13, 40, DateTime(2026, 12, 5)),
    );
    expect(
      (loan.pendingRepaymentId, loan.pendingRepaymentAmount?.value),
      ('r1', 2500000),
    );

    expect(
      [
        for (final c in home.claims)
          (
            c.kind,
            c.id,
            c.title,
            c.recordedBy,
            c.amount.value,
            c.youLent,
            c.people,
          ),
      ],
      [
        (ClaimKind.spaceMember, 'm8', 'Flat 9', 'Rahul', -75000, false, 2),
        (ClaimKind.loan, 'l2', '+919100000004', 'Kabir', 50000000, true, 0),
      ],
    );

    // Pending claims stay out of every total.
    expect(home.monthSpend.value, 1845000);
    expect(home.owed.value, 285000 + 67500000);
    expect(home.owe.value, 365000);
    expect(home.net.value, 285000 + 67500000 - 365000);
    expect(home.isEmpty, isFalse);
  });

  test('settles claims through the claim RPCs', () async {
    const space = Claim(
      kind: ClaimKind.spaceMember,
      id: 'm8',
      title: 'Flat 9',
      recordedBy: 'Rahul',
      amount: Paise.zero,
    );
    const loan = Claim(
      kind: ClaimKind.loan,
      id: 'l2',
      title: 'Kabir',
      recordedBy: 'Kabir',
      amount: Paise.zero,
    );
    String call(String rpc, String kind, String id, String key) =>
        'POST rpc/$rpc  '
        '{"p_kind":"$kind","p_id":"$id","p_idempotency_key":"$key"}';
    await repository().acceptClaim(space, idempotencyKey: 'k1');
    await repository().rejectClaim(loan, idempotencyKey: 'k2');

    expect(requests, [
      call('accept_claim', 'space_member', 'm8', 'k1'),
      call('reject_claim', 'loan', 'l2', 'k2'),
    ]);
  });

  test('a user with nothing recorded gets an empty Home', () {
    final home = HomeData(phone: '+919876543210', month: DateTime(2026, 11));
    expect(home.isEmpty, isTrue);
    expect(
      (home.owed, home.owe, home.net),
      (Paise.zero, Paise.zero, Paise.zero),
    );
  });

  group('homeRepositoryProvider', () {
    test('needs a signed-in user', () {
      final container = ProviderContainer(
        overrides: [
          supabaseClientProvider.overrideWithValue(client),
          sessionProvider.overrideWith(_NoSession.new),
        ],
      );
      addTearDown(container.dispose);
      expect(() => container.read(homeRepositoryProvider), throwsA(anything));
    });

    test('reads as the signed-in user', () {
      final container = ProviderContainer(
        overrides: [
          supabaseClientProvider.overrideWithValue(client),
          sessionProvider.overrideWith(_SignedIn.new),
        ],
      );
      addTearDown(container.dispose);
      final repository = container.read(homeRepositoryProvider);
      expect(
        repository,
        isA<SupabaseHomeRepository>().having((r) => r.userId, 'userId', _me),
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
