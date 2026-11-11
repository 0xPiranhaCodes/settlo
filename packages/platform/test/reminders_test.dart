import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:settlo_core/settlo_core.dart';
import 'package:settlo_platform/settlo_platform.dart';

Loan loan({int repaid = 0, bool youLent = false, bool closed = false}) => Loan(
  id: 'loan',
  counterparty: 'Friend',
  youLent: youLent,
  principal: const Paise(2500),
  repaid: Paise(repaid),
  startOn: DateTime(2026, 12, 20),
  installment: const Paise(1000),
  dueDay: 5,
  closed: closed,
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test(
    'account change follows an in-flight native write and drops stale writes',
    () async {
      const channel = MethodChannel('test/reminders');
      final calls = <MethodCall>[];
      final started = Completer<void>();
      final release = Completer<void>();
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (call) async {
            calls.add(call);
            if (calls.length == 1) {
              started.complete();
              await release.future;
            }
            return null;
          });
      addTearDown(
        () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(channel, null),
      );
      final notifications = ReminderNotifications(channel: channel);
      final first = notifications.replace([]);
      await started.future;
      final stale = notifications.replace([]);
      final logout = notifications.setOwner(null);
      release.complete();
      await Future.wait([first, stale, logout]);
      expect(calls.map((c) => c.method), ['replace', 'owner']);
      expect(calls.last.arguments, isNull);
    },
  );

  test('day after due at 09:00 Asia/Kolkata, including year rollover', () {
    final rows = scheduleReminders(
      [loan()],
      enabled: true,
      now: DateTime.utc(2027),
    );
    expect(rows.first.at, DateTime.utc(2027, 1, 6, 3, 30));
    expect(rows.length, 3);
    expect(rows.last.at, DateTime.utc(2027, 3, 6, 3, 30));
  });
  test('off schedules nothing', () {
    expect(
      scheduleReminders([loan()], enabled: false, now: DateTime.utc(2027)),
      isEmpty,
    );
  });
  test(
    'confirmed prepayment skips covered instalments including final fraction',
    () {
      expect(
        scheduleReminders(
          [loan(repaid: 2000)],
          enabled: true,
          now: DateTime.utc(2027),
        ).length,
        1,
      );
      expect(
        scheduleReminders(
          [loan(repaid: 2500)],
          enabled: true,
          now: DateTime.utc(2027),
        ),
        isEmpty,
      );
    },
  );
  test('no past, closed or lender reminders', () {
    expect(
      scheduleReminders([loan()], enabled: true, now: DateTime.utc(2027, 3, 7)),
      isEmpty,
    );
    expect(
      scheduleReminders(
        [loan(closed: true), loan(youLent: true)],
        enabled: true,
        now: DateTime.utc(2027),
      ),
      isEmpty,
    );
  });
  test('timezone-independent instant at India midnight on due day', () {
    final rows = scheduleReminders(
      [loan()],
      enabled: true,
      now: DateTime.parse('2027-01-05T00:00:00+05:30'),
    );
    expect(rows.first.at, DateTime.parse('2027-01-06T09:00:00+05:30'));
  });
  test(
    'unsupported platforms and permission errors do not fail sync',
    () async {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      final notifications = container.read(reminderNotificationsProvider);
      await notifications.setOwner(null);
      await notifications.replace([]);
      const channel = MethodChannel('test/reminder-denied');
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(
            channel,
            (_) async => throw PlatformException(code: 'denied'),
          );
      addTearDown(
        () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(channel, null),
      );
      await ReminderNotifications(channel: channel).replace([]);
    },
  );
  test(
    'remote push defaults off',
    () => expect(remoteRemindersEnabled, isFalse),
  );
}
