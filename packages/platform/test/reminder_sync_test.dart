import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:settlo_core/settlo_core.dart';
import 'package:settlo_core/supabase/reminders.dart';
import 'package:settlo_platform/settlo_platform.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

final fakeSession = Session(
  accessToken: 'test',
  tokenType: 'bearer',
  user: const User(
    id: 'user-a',
    appMetadata: {},
    userMetadata: {},
    aud: 'authenticated',
    createdAt: '2026-01-01T00:00:00Z',
  ),
);

class _Session extends SessionNotifier {
  new(this.initial);
  final Session? initial;
  @override
  Session? build() => initial;
  void signOut() => state = null;
}

class _Preferences implements ReminderRepository {
  bool on = true;
  @override
  Future<bool> enabled() async => on;
  @override
  Future<void> setEnabled({required bool enabled}) async {
    on = enabled;
  }

  @override
  Future<DateTime?> nextAllowed(String loanId) async => null;
  @override
  Future<DateTime> remind(String loanId) async => DateTime.utc(2027);
}

class _Notifications extends ReminderNotifications {
  final owners = <String?>[];
  final scheduled = <List<LocalReminder>>[];
  @override
  Future<void> setOwner(String? userId) async => owners.add(userId);
  @override
  Future<void> replace(List<LocalReminder> reminders) async =>
      scheduled.add(reminders);
}

Future<void> _settle() async {
  for (var i = 0; i < 20; i++) {
    await Future<void>.delayed(const Duration(milliseconds: 5));
  }
}

void main() {
  final binding = TestWidgetsFlutterBinding.ensureInitialized();
  late HttpServer server;
  late SupabaseClient client;
  final requests = <String>[];
  var preferences = <Map<String, Object?>>[];
  var cooldown = <Map<String, Object?>>[];
  var feed = <Map<String, Object?>>[];
  var fail = false;
  Completer<void>? hold;
  setUp(() async {
    HttpOverrides.global = null;
    requests.clear();
    preferences = [];
    cooldown = [];
    feed = [];
    fail = false;
    hold = null;
    server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0)
      ..listen((request) async {
        await request.drain<void>();
        final name = request.uri.path.replaceFirst('/rest/v1/', '');
        requests.add(name);
        if (name == 'rpc/activity_feed') await hold?.future;
        request.response.headers.contentType = ContentType.json;
        if (fail) {
          request.response.statusCode = 400;
          request.response.write(
            jsonEncode({'code': '22023', 'message': 'Unavailable'}),
          );
        } else {
          request.response.write(
            jsonEncode(switch (name) {
              'reminder_preferences' => preferences,
              'loan_reminders' => cooldown,
              'rpc/remind_loan' => '2027-01-01T00:00:00Z',
              'rpc/set_reminders' => null,
              'rpc/activity_feed' => feed,
              _ => <Object?>[],
            }),
          );
        }
        await request.response.close();
      });
    client = SupabaseClient(
      'http://127.0.0.1:${server.port}',
      'test',
      authOptions: const AuthClientOptions(autoRefreshToken: false),
    );
    addTearDown(() async {
      await client.dispose();
      await server.close(force: true);
    });
  });

  test(
    'repository reads server preference and cooldown and invokes writes',
    () async {
      final container = ProviderContainer(
        overrides: [
          sessionProvider.overrideWith(() => _Session(fakeSession)),
          supabaseClientProvider.overrideWithValue(client),
        ],
      );
      addTearDown(container.dispose);
      final repo = container.read(reminderRepositoryProvider);
      expect(await container.read(remindersEnabledProvider.future), isTrue);
      preferences = [
        {'enabled': false},
      ];
      expect(await repo.enabled(), isFalse);
      expect(await repo.nextAllowed('loan'), isNull);
      cooldown = [
        {'sent_at': '2026-12-31T00:00:00Z'},
      ];
      expect(await repo.nextAllowed('loan'), DateTime.utc(2027));
      await repo.setEnabled(enabled: false);
      expect(await repo.remind('loan'), DateTime.utc(2027));
      expect(requests, containsAll(['rpc/set_reminders', 'rpc/remind_loan']));
    },
  );

  test(
    'sync respects preference, refreshes on resume, drops held logout response',
    () async {
      final repo = _Preferences()..on = false;
      final native = _Notifications();
      final container = ProviderContainer(
        overrides: [
          sessionProvider.overrideWith(() => _Session(fakeSession)),
          supabaseClientProvider.overrideWithValue(client),
          reminderRepositoryProvider.overrideWithValue(repo),
          reminderNotificationsProvider.overrideWithValue(native),
        ],
      );
      addTearDown(container.dispose);
      container.listen(reminderSyncProvider, (_, _) {});
      await _settle();
      expect(native.scheduled.last, isEmpty);
      expect(requests, isEmpty);
      repo.on = true;
      feed = [
        {
          'id': 1,
          'created_at': DateTime.now().toUtc().toIso8601String(),
          'kind': 'loan',
          'action': 'reminded',
          'by_me': false,
          'loan_id': 'loan',
        },
      ];
      container.read(ledgerRevisionProvider.notifier).bump();
      await _settle();
      expect(native.scheduled.last.single.id, 'manual:1');
      final count = requests.length;
      binding
        ..handleAppLifecycleStateChanged(AppLifecycleState.inactive)
        ..handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await _settle();
      expect(requests.length, greaterThan(count));
      hold = Completer<void>();
      container.read(ledgerRevisionProvider.notifier).bump();
      await _settle();
      (container.read(sessionProvider.notifier) as _Session).signOut();
      await _settle();
      expect(native.owners.last, isNull);
      final schedules = native.scheduled.length;
      hold!.complete();
      await _settle();
      expect(native.scheduled.length, schedules);
    },
  );

  test('offline refresh preserves the same account schedule', () async {
    final native = _Notifications();
    final container = ProviderContainer(
      overrides: [
        sessionProvider.overrideWith(() => _Session(fakeSession)),
        supabaseClientProvider.overrideWithValue(client),
        reminderRepositoryProvider.overrideWithValue(_Preferences()),
        reminderNotificationsProvider.overrideWithValue(native),
      ],
    );
    addTearDown(container.dispose);
    fail = true;
    container.listen(reminderSyncProvider, (_, _) {});
    await _settle();
    expect(native.owners.single, fakeSession.user.id);
    expect(native.scheduled, isEmpty);
  });
}
