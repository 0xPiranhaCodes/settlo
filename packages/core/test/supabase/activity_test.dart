import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:settlo_core/settlo_core.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Rows as PostgREST returns them from the views.
final _views = <String, List<Map<String, Object?>>>{
  'activity_feed': [
    // Rahul edited the wifi bill.
    {
      'id': 42,
      'created_at': '2026-11-09T08:30:00Z',
      'kind': 'expense',
      'action': 'edited',
      'by_me': false,
      'space_id': 's1',
      'space_name': 'Flat 402',
      'loan_id': null,
      'actor_name': 'Rahul',
      'counterparty': null,
      'description': 'Wifi · Airtel',
      'amount_minor': 119900,
      'before_description': 'Wifi',
      'before_amount_minor': 109900,
      'status': null,
      'my_side': null,
    },
    // Arjun repaid you, and you confirmed.
    {
      'id': 41,
      'created_at': '2026-11-05T10:00:00Z',
      'kind': 'repayment',
      'action': 'confirmed',
      'by_me': true,
      'space_id': null,
      'space_name': null,
      'loan_id': 'l1',
      'actor_name': null,
      'counterparty': 'Arjun',
      'description': null,
      'amount_minor': 2500000,
      'before_description': null,
      'before_amount_minor': null,
      'status': 'confirmed',
      'my_side': 'in',
    },
  ],
  'needs_you': [
    {
      'kind': 'repayment',
      'id': 'r3',
      'space_id': null,
      'space_name': null,
      'loan_id': 'l1',
      'counterparty': 'Arjun',
      'amount_minor': 2500000,
      'paid_on': '2026-10-05',
      'created_at': '2026-10-05T09:00:00Z',
    },
    {
      'kind': 'settlement',
      'id': 'e9',
      'space_id': 's2',
      'space_name': 'Goa trip',
      'loan_id': null,
      'counterparty': 'Kabir',
      'amount_minor': 120000,
      'paid_on': '2026-11-02',
      'created_at': '2026-11-02T09:00:00Z',
    },
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
        final path = request.uri.path.replaceFirst('/rest/v1/', '');
        requests.add('${request.method} $path ${request.uri.query}');
        request.response
          ..headers.contentType = ContentType.json
          ..write(jsonEncode(_views[path]));
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

  ActivityRepository repository() => SupabaseActivityRepository(client);

  test('feed reads the newest page, with before and after values', () async {
    final [edit, repaid] = await repository().feed(limit: 30);
    expect(requests.single, startsWith('GET activity_feed select='));
    expect(requests.single, contains('order=id.desc.nullslast&limit=30'));
    expect(
      (edit.id, edit.kind, edit.action, edit.byYou, edit.actor),
      (42, ActivityKind.expense, ActivityAction.edited, false, 'Rahul'),
    );
    expect((edit.spaceId, edit.spaceName), ('s1', 'Flat 402'));
    expect(
      (edit.beforeDescription, edit.description),
      ('Wifi', 'Wifi · Airtel'),
    );
    expect(
      (edit.beforeAmount, edit.amount),
      (const Paise(109900), const Paise(119900)),
    );
    expect(
      (edit.status, edit.toYou, edit.tone),
      (null, null, MoneyTone.neutral),
    );
    expect(edit.at, DateTime.utc(2026, 11, 9, 8, 30));
    expect(
      (repaid.kind, repaid.loanId, repaid.counterparty, repaid.byYou),
      (ActivityKind.repayment, 'l1', 'Arjun', true),
    );
    expect(
      (repaid.status, repaid.toYou, repaid.tone),
      (ActivityStatus.confirmed, true, MoneyTone.owedToYou),
    );
    expect(repaid.beforeAmount, isNull);
  });

  test('the next page starts below the last id seen (keyset)', () async {
    await repository().feed(before: 41, limit: 2);
    expect(requests.single, contains('id=lt.41'));
    expect(requests.single, contains('order=id.desc.nullslast&limit=2'));
    expect(requests.single, isNot(contains('offset')));
  });

  test('needsYou reads repayments and settle-ups, newest first', () async {
    final [repayment, settleUp] = await repository().needsYou();
    expect(requests.single, endsWith('order=created_at.desc.nullslast'));
    expect(
      (repayment.id, repayment.isRepayment, repayment.loanId),
      ('r3', true, 'l1'),
    );
    expect(
      (repayment.counterparty, repayment.amount, repayment.paidOn),
      ('Arjun', const Paise.rupees(25000), DateTime(2026, 10, 5)),
    );
    expect(
      (settleUp.id, settleUp.isRepayment, settleUp.spaceId),
      ('e9', false, 's2'),
    );
    expect(
      (settleUp.spaceName, settleUp.amount, settleUp.recordedAt),
      ('Goa trip', const Paise.rupees(1200), DateTime.utc(2026, 11, 2, 9)),
    );
  });

  group('tone', () {
    ActivityEntry entry(ActivityStatus? status, {bool? toYou}) => ActivityEntry(
      id: 1,
      at: DateTime(2026),
      kind: ActivityKind.settlement,
      action: ActivityAction.created,
      byYou: false,
      status: status,
      toYou: toYou,
    );

    test('confirmed money is mint to you and coral from you', () {
      expect(
        entry(ActivityStatus.confirmed, toYou: true).tone,
        MoneyTone.owedToYou,
      );
      expect(
        entry(ActivityStatus.confirmed, toYou: false).tone,
        MoneyTone.youOwe,
      );
    });

    test('money that never counted is grey', () {
      expect(
        entry(ActivityStatus.disputed, toYou: true).tone,
        MoneyTone.settled,
      );
      expect(
        entry(ActivityStatus.deleted, toYou: false).tone,
        MoneyTone.settled,
      );
    });

    test('waiting, or not yours, is uncoloured', () {
      expect(
        entry(ActivityStatus.pending, toYou: true).tone,
        MoneyTone.neutral,
      );
      expect(entry(ActivityStatus.confirmed).tone, MoneyTone.neutral);
    });
  });
}
