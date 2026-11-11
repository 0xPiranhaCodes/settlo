import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:settlo_core/settlo_core.dart';
import 'package:settlo_core/supabase/reminders.dart';
import 'package:settlo_platform/settlo_platform.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

Session _session(String id) => Session(
  accessToken: 'test',
  tokenType: 'bearer',
  user: User(
    id: id,
    appMetadata: const {},
    userMetadata: const {},
    aud: 'authenticated',
    createdAt: '2026-01-01T00:00:00Z',
  ),
);

class _Session extends SessionNotifier {
  @override
  Session? build() => _session('a');
  void switchTo(String? id) => state = id == null ? null : _session(id);
}

class _Preferences implements ReminderRepository {
  bool on = true;
  bool fail = false;
  int reads = 0;
  @override
  Future<bool> enabled() async {
    reads++;
    if (fail) throw Exception('offline');
    return on;
  }

  @override
  Future<void> setEnabled({required bool enabled}) async => on = enabled;
  @override
  Future<ReminderCooldown?> nextAllowed(String loanId) async => null;
  @override
  Future<DateTime> remind(String loanId) async => DateTime.utc(2027);
}

LoansData _loans({bool scheduled = true, bool empty = false}) => LoansData(
  today: DateTime(2026),
  loans: [
    if (!empty)
      Loan(
        id: 'loan',
        counterparty: 'Friend',
        youLent: false,
        principal: const Paise(10000),
        repaid: Paise.zero,
        startOn: DateTime(2026),
        installment: scheduled ? const Paise(1000) : null,
      ),
  ],
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('test/reminder-permission-ui');
  late String status;
  late Set<String> claimed;
  late List<String> calls;
  late String? failingMethod;
  late Completer<String>? heldStatus;
  late _Preferences preferences;
  late ProviderContainer container;
  late LoansData data;
  late Future<LoansData> Function() snapshot;
  setUp(() {
    status = 'notDetermined';
    claimed = {};
    calls = [];
    failingMethod = null;
    heldStatus = null;
    preferences = _Preferences();
    data = _loans(empty: true);
    snapshot = () async => data;
    container = ProviderContainer(
      overrides: [
        sessionProvider.overrideWith(_Session.new),
        reminderRepositoryProvider.overrideWith((ref) {
          ref.watch(sessionProvider);
          return preferences;
        }),
        reminderNotificationsProvider.overrideWithValue(
          ReminderNotifications(channel: channel),
        ),
        acceptedLoanSnapshotProvider.overrideWithValue(() => snapshot()),
      ],
    );
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          calls.add(call.method);
          if (call.method == failingMethod) {
            throw PlatformException(code: 'unavailable');
          }
          switch (call.method) {
            case 'permissionStatus':
              return heldStatus == null ? status : await heldStatus!.future;
            case 'claimPrompt':
              return status == 'notDetermined' &&
                  claimed.add(call.arguments as String);
            case 'requestPermission':
              status = 'granted';
          }
          return null;
        });
  });
  tearDown(() {
    container.dispose();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
  });
  Future<void> pump(WidgetTester tester) async {
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          home: AcceptedLoanReminderPrompt(
            child: Scaffold(
              body: Consumer(
                builder: (context, ref, _) => TextButton(
                  onPressed: () => showReminderPermission(
                    context,
                    ref,
                    ReminderPermissionTrigger.remind,
                  ),
                  child: const Text('Remind'),
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  Future<void> tapRemind(WidgetTester tester) async {
    await tester.tap(find.text('Remind'));
    await tester.pumpAndSettle();
  }

  for (final permission in ['notDetermined', 'granted', 'denied']) {
    testWidgets('dialog and explicit permission request: $permission', (
      tester,
    ) async {
      status = permission;
      await pump(tester);
      expect(calls, isEmpty, reason: 'Cold launch must never prompt');
      await tapRemind(tester);
      if (permission == 'notDetermined') {
        expect(find.text('Get reminder notifications?'), findsOneWidget);
        expect(claimed, {'remind'});
        expect(calls, isNot(contains('requestPermission')));
        await tester.tap(find.text('Continue'));
        await tester.pumpAndSettle();
        expect(
          calls.where((call) => call == 'requestPermission'),
          hasLength(1),
        );
      } else {
        expect(claimed, isEmpty);
        expect(find.byType(AlertDialog), findsNothing);
      }
      final count = calls.where((call) => call == 'requestPermission').length;
      await tapRemind(tester);
      expect(find.byType(AlertDialog), findsNothing);
      expect(
        calls.where((call) => call == 'requestPermission'),
        hasLength(count),
      );
    });
  }
  for (final dismiss in ['Not now', 'barrier']) {
    testWidgets('$dismiss consumes context without nagging', (tester) async {
      await pump(tester);
      await tapRemind(tester);
      expect(claimed, {'remind'});
      if (dismiss == 'barrier') {
        await tester.tapAt(const Offset(5, 5));
      } else {
        await tester.tap(find.text(dismiss));
      }
      await tester.pumpAndSettle();
      await tapRemind(tester);
      expect(find.byType(AlertDialog), findsNothing);
      expect(calls, isNot(contains('requestPermission')));
    });
  }
  testWidgets('explanation invalidates preference snapshot', (tester) async {
    final subscription = container.listen(remindersEnabledProvider, (_, _) {});
    addTearDown(subscription.close);
    expect(await container.read(remindersEnabledProvider.future), isTrue);
    await pump(tester);
    await tapRemind(tester);
    preferences.on = false;
    await tester.tap(find.text('Not now'));
    await tester.pumpAndSettle();
    expect(await container.read(remindersEnabledProvider.future), isFalse);
  });
  for (final failure in [
    'permissionStatus',
    'claimPrompt',
    'requestPermission',
    'preference',
  ]) {
    testWidgets('$failure failure does not escape permission UX', (
      tester,
    ) async {
      failingMethod = failure;
      preferences.fail = failure == 'preference';
      await pump(tester);
      await tapRemind(tester);
      if (failure == 'requestPermission') {
        await tester.tap(find.text('Continue'));
        await tester.pumpAndSettle();
      }
      expect(find.byType(AlertDialog), findsNothing);
      expect(tester.takeException(), isNull);
      if (failure != 'requestPermission') {
        expect(calls, isNot(contains('requestPermission')));
      }
    });
  }
  testWidgets('disabled reminders do not consume pre-prompt', (tester) async {
    preferences.on = false;
    await pump(tester);
    await tapRemind(tester);
    expect(claimed, isEmpty);
    preferences.on = true;
    await tapRemind(tester);
    expect(find.byType(AlertDialog), findsOneWidget);
    await tester.tap(find.text('Not now'));
    await tester.pumpAndSettle();
  });
  testWidgets('account switch in dialog fences native request', (tester) async {
    await pump(tester);
    await tapRemind(tester);
    preferences = _Preferences();
    (container.read(sessionProvider.notifier) as _Session).switchTo('b');
    await tester.pump();
    await tester.tap(find.text('Continue'));
    await tester.pumpAndSettle();
    expect(calls, isNot(contains('requestPermission')));
    expect(preferences.reads, 0);
  });
  testWidgets('unmounted caller drops held permission status', (tester) async {
    heldStatus = Completer<String>();
    await pump(tester);
    await tester.tap(find.text('Remind'));
    await tester.pump();
    await tester.pumpWidget(const SizedBox());
    heldStatus!.complete('notDetermined');
    await tester.pumpAndSettle();
    expect(claimed, isEmpty);
    expect(tester.takeException(), isNull);
  });
  for (final scheduled in [false, true]) {
    test(
      'only newly accepted scheduled loans emit events: $scheduled',
      () async {
        final notifier = container.read(acceptedLoanReminderProvider.notifier);
        expect(container.read(acceptedLoanReminderProvider), isNull);
        await notifier.redeem(() async => data = _loans(scheduled: scheduled));
        expect(
          container.read(acceptedLoanReminderProvider),
          scheduled ? 'a' : null,
        );
        notifier.clear();
        await notifier.redeem(() async {});
        expect(container.read(acceptedLoanReminderProvider), isNull);
      },
    );
  }
  test('signed-out redemption delegates without snapshots', () async {
    (container.read(sessionProvider.notifier) as _Session).switchTo(null);
    snapshot = () => throw StateError('must not load');
    var redeemed = false;
    await container.read(acceptedLoanReminderProvider.notifier).redeem(
      () async {
        redeemed = true;
      },
    );
    expect(redeemed, isTrue);
    expect(container.read(acceptedLoanReminderProvider), isNull);
  });
  for (final failingSnapshot in [1, 2]) {
    test('snapshot $failingSnapshot failure never fails redemption', () async {
      var reads = 0;
      var redeemed = false;
      snapshot = () async {
        if (++reads == failingSnapshot) throw StateError('offline');
        return data;
      };
      await container.read(acceptedLoanReminderProvider.notifier).redeem(
        () async {
          redeemed = true;
          data = _loans();
        },
      );
      expect(redeemed, isTrue);
      expect(container.read(acceptedLoanReminderProvider), isNull);
      expect(reads, failingSnapshot);
    });
  }
  test('failed redemption propagates without acceptance', () async {
    final error = Exception('redemption failed');
    await expectLater(
      container
          .read(acceptedLoanReminderProvider.notifier)
          .redeem(() async => throw error),
      throwsA(same(error)),
    );
    expect(container.read(acceptedLoanReminderProvider), isNull);
  });
  for (final stage in ['before', 'action', 'after']) {
    for (final nextAccount in [null, 'b']) {
      test(
        'account change to $nextAccount during $stage fences acceptance',
        () async {
          final held = Completer<LoansData>();
          final entered = Completer<void>();
          var reads = 0;
          var redeemed = false;
          snapshot = () async {
            reads++;
            if ((stage == 'before' && reads == 1) ||
                (stage == 'after' && reads == 2)) {
              entered.complete();
              return await held.future;
            }
            return data;
          };
          void switchAccount() =>
              (container.read(sessionProvider.notifier) as _Session).switchTo(
                nextAccount,
              );
          final pending = container
              .read(acceptedLoanReminderProvider.notifier)
              .redeem(() async {
                redeemed = true;
                data = _loans();
                if (stage == 'action') switchAccount();
              });
          if (stage != 'action') {
            await entered.future;
            switchAccount();
            final assertion = stage == 'before'
                ? expectLater(pending, throwsA(isA<SessionEnded>()))
                : expectLater(pending, completes);
            held.complete(data);
            await assertion;
          } else {
            await pending;
          }
          expect(redeemed, stage != 'before');
          expect(container.read(acceptedLoanReminderProvider), isNull);
        },
      );
    }
  }
  testWidgets('acceptance host consumes event and prompts once', (
    tester,
  ) async {
    await pump(tester);
    await container
        .read(acceptedLoanReminderProvider.notifier)
        .redeem(() async => data = _loans());
    await tester.pumpAndSettle();
    expect(container.read(acceptedLoanReminderProvider), isNull);
    expect(claimed, {'instalmentLoan'});
    expect(find.byType(AlertDialog), findsOneWidget);
    await tester.tap(find.text('Continue'));
    await tester.pumpAndSettle();
    await pump(tester);
    expect(calls.where((call) => call == 'requestPermission'), hasLength(1));
  });
  testWidgets('old account acceptance is cleared without prompting', (
    tester,
  ) async {
    await container
        .read(acceptedLoanReminderProvider.notifier)
        .redeem(() async => data = _loans());
    (container.read(sessionProvider.notifier) as _Session).switchTo('b');
    await pump(tester);
    expect(container.read(acceptedLoanReminderProvider), isNull);
    expect(calls, isEmpty);
  });
  test('live snapshot provider rebuilds on account change', () async {
    final client = SupabaseClient('http://localhost:1', 'test');
    addTearDown(client.dispose);
    final live = ProviderContainer(
      overrides: [
        sessionProvider.overrideWith(_Session.new),
        supabaseClientProvider.overrideWithValue(client),
      ],
    );
    addTearDown(live.dispose);
    // Resolving the tear-off stays lazy and performs no network request.
    final signedIn = live.read(acceptedLoanSnapshotProvider);
    expect(signedIn, isA<Future<LoansData> Function()>());
    (live.read(sessionProvider.notifier) as _Session).switchTo(null);
    expect(live.read(acceptedLoanSnapshotProvider), isNot(same(signedIn)));
  });
}
