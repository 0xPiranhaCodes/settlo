import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:settlo_platform/settlo_platform.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('test/contextual-reminders');
  late String status;
  late Set<String> seen;
  late int requests;
  late int explanations;
  late ReminderNotifications notifications;
  setUp(() {
    status = 'notDetermined';
    seen = {};
    requests = 0;
    explanations = 0;
    notifications = ReminderNotifications(channel: channel);
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          switch (call.method) {
            case 'permissionStatus':
              return status;
            case 'claimPrompt':
              return status == 'notDetermined' &&
                  seen.add(call.arguments as String);
            case 'requestPermission':
              requests++;
              status = 'denied';
          }
          return null;
        });
  });
  tearDown(
    () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null),
  );

  Future<void> prompt(
    ReminderPermissionTrigger trigger, {
    bool accept = true,
    bool enabled = true,
  }) => notifications.promptInContext(
    trigger,
    enabled: () async => enabled,
    active: () => true,
    explain: () async {
      explanations++;
      return accept;
    },
  );

  for (final trigger in ReminderPermissionTrigger.values) {
    for (final permission in ['notDetermined', 'denied', 'granted']) {
      test('${trigger.name}: $permission', () async {
        status = permission;
        await prompt(trigger);
        expect(explanations, permission == 'notDetermined' ? 1 : 0);
        expect(requests, permission == 'notDetermined' ? 1 : 0);
        for (final other in ReminderPermissionTrigger.values) {
          await prompt(other);
        }
        expect(requests, permission == 'notDetermined' ? 1 : 0);
      });
    }
    test('${trigger.name}: opt-out does not consume context', () async {
      await prompt(trigger, enabled: false);
      expect(seen, isEmpty);
      await prompt(trigger);
      expect(requests, 1);
    });
    test(
      '${trigger.name}: dismissal survives a new service instance',
      () async {
        await prompt(trigger, accept: false);
        notifications = ReminderNotifications(channel: channel);
        await prompt(trigger);
        expect(explanations, 1);
        expect(requests, 0);
        for (final other in ReminderPermissionTrigger.values.where(
          (value) => value != trigger,
        )) {
          await prompt(other, accept: false);
        }
        expect(explanations, 3);
      },
    );
  }
  test('concurrent contexts show only one dialog', () async {
    final held = Completer<bool>();
    final first = notifications.promptInContext(
      ReminderPermissionTrigger.remind,
      enabled: () async => true,
      active: () => true,
      explain: () => held.future,
    );
    await Future<void>.delayed(Duration.zero);
    await prompt(ReminderPermissionTrigger.profile);
    expect(explanations, 0);
    held.complete(false);
    await first;
  });
  test('unmounted context never requests the system prompt', () async {
    var active = true;
    await notifications.promptInContext(
      ReminderPermissionTrigger.remind,
      enabled: () async => true,
      active: () => active,
      explain: () async {
        active = false;
        return true;
      },
    );
    expect(requests, 0);
  });
}
