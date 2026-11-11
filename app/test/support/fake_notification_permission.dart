import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

/// Models persistent OS status and per-context native claims across widgets.
class FakeNotificationPermission {
  new(this.status);

  String status;
  final seen = <String>{};
  final calls = <String>[];
  int requests = 0;

  void install() {
    const channel = MethodChannel('app.settlo/reminders');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          calls.add(call.method);
          switch (call.method) {
            case 'permissionStatus':
              return status;
            case 'claimPrompt':
              return status == 'notDetermined' &&
                  seen.add(call.arguments as String);
            case 'requestPermission':
              requests++;
              status = 'granted';
          }
          return null;
        });
    addTearDown(
      () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, null),
    );
  }
}
