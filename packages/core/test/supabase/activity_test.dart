import 'dart:convert';
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:settlo_core/settlo_core.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Rows as PostgREST returns them from the views.
final _views = <String, List<Map<String, Object?>>?>{
  // You last looked on 6 Nov: Rahul's edit is new, your own entry is not.
  'activity_seen': [
    {'seen_at': '2026-11-06T00:00:00+00:00'},
  ],
  'rpc/mark_activity_seen': null,
  'rpc/question_activity': null,
  'rpc/activity_feed': [
    // Rahul edited the wifi bill.
    {
      'id': 42,
      'created_at': '2026-11-09T08:30:00.123456+00:00',
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
      'link_only': true,
      'questions': [
        {
          'by_me': false,
          'name': 'Priya',
          'note': 'Why? Call ९८००० ००००९',
          'created_at': '2026-11-09T10:00:00.5+00:00',
        },
      ],
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

class _NoSession extends SessionNotifier {
  @override
  Session? build() => null;
}

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
    expect(requests.single, 'POST rpc/activity_feed  {"p_limit":30}');
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
    expect(edit.at, DateTime.utc(2026, 11, 9, 8, 30, 0, 123, 456));
    expect(edit.linkOnly, isTrue);
    expect(
      (repaid.kind, repaid.loanId, repaid.counterparty, repaid.byYou),
      (ActivityKind.repayment, 'l1', 'Arjun', true),
    );
    expect(
      (repaid.status, repaid.toYou, repaid.tone),
      (ActivityStatus.confirmed, true, MoneyTone.owedToYou),
    );
    expect(repaid.beforeAmount, isNull);
    expect(repaid.linkOnly, isFalse);
  });

  test('the next page starts below the last row, by time then id', () async {
    final [edit, _] = await repository().feed(limit: 30);
    requests.clear();
    await repository().feed(before: edit, limit: 2);
    // The exact microsecond goes back, so no row at that instant is lost.
    expect(
      requests.single,
      'POST rpc/activity_feed  ${jsonEncode({'p_limit': 2, 'p_before_at': '2026-11-09T08:30:00.123456Z', 'p_before_id': 42})}',
    );
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

  group('filters, unread and questions (#109)', () {
    test('a filter goes to the server with the same cursor', () async {
      final [edit, _] = await repository().feed(limit: 30);
      requests.clear();
      await repository().feed(
        limit: 30,
        filter: (spaceId: 's1', loansOnly: false),
      );
      await repository().feed(
        limit: 30,
        before: edit,
        filter: (spaceId: null, loansOnly: true),
      );
      expect(requests, [
        'POST rpc/activity_feed  {"p_limit":30,"p_space_id":"s1"}',
        'POST rpc/activity_feed  ${jsonEncode({'p_limit': 30, 'p_loans_only': true, 'p_before_at': '2026-11-09T08:30:00.123456Z', 'p_before_id': 42})}',
      ]);
    });

    test('an entry is in a filter as the server decides it', () async {
      final [edit, repaid] = await repository().feed(limit: 30);
      const flat = (spaceId: 's1', loansOnly: false);
      const trip = (spaceId: 's2', loansOnly: false);
      const loans = (spaceId: null, loansOnly: true);
      expect(
        [
          for (final f in [allActivity, flat, trip, loans]) edit.isIn(f),
        ],
        [true, true, false, false],
      );
      expect(
        [
          for (final f in [allActivity, flat, trip, loans]) repaid.isIn(f),
        ],
        [true, false, false, true],
      );
      // A space and loans together match nothing, as on the server.
      expect(repaid.isIn((spaceId: 's1', loansOnly: true)), isFalse);
      expect(edit.isIn((spaceId: 's1', loansOnly: true)), isFalse);
    });

    test('unread counts what is not yours since you last looked', () async {
      expect(await repository().unread(), 1);
      expect(requests, [
        'GET activity_seen select=seen_at',
        'POST rpc/activity_feed  {"p_limit":100}',
      ]);
      final entries = await repository().feed(limit: 30);
      // Never looked: everything of other people's. Looked since: nothing.
      expect(unreadIn(entries, null), 1);
      expect(unreadIn(entries, DateTime.utc(2026, 11, 9, 9)), 0);
      expect(seenAtFromRows(const []), isNull);
    });

    test(
      'markSeen sends the exact time of the newest entry or question',
      () async {
        // Priya's question is newer than the edit it is on.
        await repository().markSeen();
        expect(requests, [
          'POST rpc/activity_feed  {"p_limit":100}',
          'POST rpc/mark_activity_seen  {"p_at":"2026-11-09T10:00:00.500Z"}',
        ]);
      },
    );

    test('a question rings for the editor only', () {
      final seen = DateTime(2026, 11, 9, 12);
      ActivityEntry edit({required bool byYou, required bool askedByYou}) =>
          ActivityEntry(
            id: 1,
            at: DateTime(2026, 11, 9, 9),
            kind: ActivityKind.expense,
            action: ActivityAction.edited,
            byYou: byYou,
            spaceId: 's1',
            questions: [
              (
                byYou: askedByYou,
                name: askedByYou ? null : 'Priya',
                note: 'Why?',
                at: DateTime(2026, 11, 9, 13),
              ),
              // Still queued on this device: no time yet.
              (byYou: askedByYou, name: null, note: 'Why?', at: null),
            ],
          );
      // Your edit, asked about after you last looked: one unread.
      final yours = edit(byYou: true, askedByYou: false);
      expect(unreadIn([yours], seen), 1);
      expect(unreadIn([yours], DateTime(2026, 11, 9, 14)), 0);
      // Someone else's edit, already seen: the question is not yours to
      // answer, whoever asked it.
      expect(unreadIn([edit(byYou: false, askedByYou: false)], seen), 0);
      expect(unreadIn([edit(byYou: false, askedByYou: true)], seen), 0);
      // Seeing the feed moves the cursor past the question.
      expect(newestIn([yours]), DateTime(2026, 11, 9, 13));
      expect(newestIn(const []), isNull);
    });

    test('markSeen with an empty feed sends nothing', () async {
      final feed = _views['rpc/activity_feed'];
      _views['rpc/activity_feed'] = [];
      addTearDown(() => _views['rpc/activity_feed'] = feed);
      await repository().markSeen();
      expect(requests, ['POST rpc/activity_feed  {"p_limit":100}']);
    });

    test('a question is trimmed and loses its phone numbers before it is '
        'sent, and again when read', () async {
      final [edit, repaid] = await repository().feed(limit: 30);
      expect(edit.questions.single, (
        byYou: false,
        name: 'Priya',
        note: 'Why? Call ••••',
        at: DateTime.utc(2026, 11, 9, 10, 0, 0, 500),
      ));
      expect(repaid.questions, isEmpty);
      requests.clear();

      await repository().question(edit, '  Why ₹100 more? +91 98000 00009 ');
      expect(
        requests.single,
        'POST rpc/question_activity  '
        '${jsonEncode({'p_activity_id': 42, 'p_note': 'Why ₹100 more? ••••'})}',
      );
    });

    test('the bell provider counts through the repository', () async {
      final container = ProviderContainer(
        overrides: [
          supabaseClientProvider.overrideWithValue(client),
          sessionProvider.overrideWith(_NoSession.new),
        ],
      );
      addTearDown(container.dispose);
      expect(await container.read(activityUnreadProvider.future), 1);
    });

    test("only someone else's edit in a space, not yet questioned by you, "
        'can be questioned', () {
      ActivityEntry entry({
        ActivityAction action = ActivityAction.edited,
        bool byYou = false,
        String? spaceId = 's1',
        List<ActivityQuestion> questions = const [],
      }) => ActivityEntry(
        id: 1,
        at: DateTime(2026, 11, 9),
        kind: ActivityKind.expense,
        action: action,
        byYou: byYou,
        spaceId: spaceId,
        questions: questions,
      );
      expect(entry().canQuestion, isTrue);
      expect(
        entry(
          questions: [(byYou: false, name: 'Priya', note: 'Why?', at: null)],
        ).canQuestion,
        isTrue,
      );
      expect(entry(action: ActivityAction.created).canQuestion, isFalse);
      expect(entry(byYou: true).canQuestion, isFalse);
      expect(entry(spaceId: null).canQuestion, isFalse);
      expect(
        entry(questions: [(byYou: true, name: null, note: 'Why?', at: null)])
            .canQuestion,
        isFalse,
      );
    });
  });
}
