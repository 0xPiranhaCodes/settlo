import 'dart:async';

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:settlo_core/settlo_core.dart';
import 'package:settlo_core/supabase/reminders.dart';
import 'package:settlo_profile/src/reminder_toggle.dart';

class _Repository implements ReminderRepository {
  bool on = true;
  bool failRead = false;
  bool failWrite = false;
  int writes = 0;
  Completer<void>? held;
  @override
  Future<bool> enabled() async {
    if (failRead) throw Exception('offline');
    return on;
  }

  @override
  Future<void> setEnabled({required bool enabled}) async {
    writes++;
    await held?.future;
    if (failWrite) throw Exception('offline');
    on = enabled;
  }

  @override
  Future<ReminderCooldown?> nextAllowed(String loanId) async => null;
  @override
  Future<DateTime> remind(String loanId) async => DateTime.utc(2027);
}

Future<void> _pump(WidgetTester tester, _Repository repo) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: [reminderRepositoryProvider.overrideWithValue(repo)],
      child: MaterialApp(
        theme: SettloTheme.light(),
        home: const Scaffold(
          body: SingleChildScrollView(child: ReminderToggle()),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  for (final status in ['notDetermined', 'denied', 'granted']) {
    for (final accept in [false, true]) {
      testWidgets('asks only when turned on: $status, continue=$accept', (
        tester,
      ) async {
        const channel = MethodChannel('app.settlo/reminders');
        final calls = <String>[];
        final seen = <String>{};
        var permission = status;
        tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          channel,
          (call) async {
            calls.add(call.method);
            if (call.method == 'permissionStatus') return permission;
            if (call.method == 'claimPrompt') {
              return seen.add(call.arguments as String);
            }
            if (call.method == 'requestPermission') permission = 'granted';
            return null;
          },
        );
        addTearDown(
          () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
            channel,
            null,
          ),
        );
        final repo = _Repository()..on = false;
        await _pump(tester, repo);
        // Opening Profile never asks (#259).
        expect(find.text('Get reminder notifications?'), findsNothing);
        expect(calls, isNot(contains('claimPrompt')));
        await tester.tap(find.byType(Switch));
        await tester.pumpAndSettle();
        expect(
          find.text('Get reminder notifications?'),
          status == 'notDetermined' ? findsOneWidget : findsNothing,
        );
        if (status == 'notDetermined') {
          await tester.tap(find.text(accept ? 'Continue' : 'Not now'));
          await tester.pumpAndSettle();
        }
        expect(
          calls.where((c) => c == 'requestPermission').length,
          status == 'notDetermined' && accept ? 1 : 0,
        );
        if (status == 'denied') {
          expect(
            find.text('Notifications are off in iOS Settings.'),
            findsOneWidget,
          );
          await tester.tap(find.text('Open Settings'));
          await tester.pumpAndSettle();
          expect(calls, contains('openSettings'));
        }
        await tester.pumpWidget(const SizedBox());
        await _pump(tester, repo);
        expect(find.text('Get reminder notifications?'), findsNothing);
        await tester.tap(find.byType(Switch));
        await tester.pumpAndSettle();
        await tester.tap(find.byType(Switch));
        await tester.pumpAndSettle();
        expect(find.text('Get reminder notifications?'), findsNothing);
      });
    }
  }
  testWidgets('opening default-on reminders never asks (#259)', (tester) async {
    const channel = MethodChannel('app.settlo/reminders');
    final calls = <String>[];
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(channel, (
      call,
    ) async {
      calls.add(call.method);
      return switch (call.method) {
        'permissionStatus' => 'notDetermined',
        'claimPrompt' => true,
        _ => null,
      };
    });
    addTearDown(
      () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        channel,
        null,
      ),
    );
    await _pump(tester, _Repository());
    expect(find.text('Get reminder notifications?'), findsNothing);
    expect(calls, isNot(contains('claimPrompt')));
  });
  testWidgets(
    'iOS explains with a native alert',
    variant: TargetPlatformVariant.only(TargetPlatform.iOS),
    (tester) async {
      const channel = MethodChannel('app.settlo/reminders');
      var requested = false;
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        channel,
        (call) async => switch (call.method) {
          'permissionStatus' => requested ? 'granted' : 'notDetermined',
          'claimPrompt' => true,
          'requestPermission' => requested = true,
          _ => null,
        },
      );
      addTearDown(
        () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          channel,
          null,
        ),
      );
      await _pump(tester, _Repository()..on = false);
      await tester.tap(find.byType(Switch));
      await tester.pumpAndSettle();
      expect(find.byType(CupertinoAlertDialog), findsOneWidget);
      expect(find.byType(AlertDialog), findsNothing);
      await tester.tap(find.text('Continue'));
      await tester.pumpAndSettle();
      expect(requested, isTrue);
    },
  );
  testWidgets('one pending write, saved preference survives reopening', (
    tester,
  ) async {
    final repo = _Repository()..held = Completer<void>();
    await _pump(tester, repo);
    await tester.tap(find.byType(Switch));
    await tester.tap(find.byType(Switch));
    expect(repo.writes, 1);
    repo.held!.complete();
    await tester.pumpAndSettle();
    expect(tester.widget<Switch>(find.byType(Switch)).value, isFalse);
    await tester.pumpWidget(const SizedBox());
    await _pump(tester, repo);
    expect(tester.widget<Switch>(find.byType(Switch)).value, isFalse);
  });
  testWidgets('load retry and failed save preserve server preference', (
    tester,
  ) async {
    final repo = _Repository()..failRead = true;
    await _pump(tester, repo);
    expect(find.text("Couldn't load reminders."), findsOneWidget);
    repo.failRead = false;
    await tester.tap(find.text('Try again'));
    await tester.pumpAndSettle();
    repo.failWrite = true;
    await tester.tap(find.byType(Switch));
    await tester.pumpAndSettle();
    expect(
      find.text("Couldn't save reminders. Please try again."),
      findsOneWidget,
    );
    expect(tester.widget<Switch>(find.byType(Switch)).value, isTrue);
  });
  testWidgets('a held save can finish after the screen closes', (tester) async {
    final repo = _Repository()..held = Completer<void>();
    await _pump(tester, repo);
    await tester.tap(find.byType(Switch));
    await tester.pumpWidget(const SizedBox());
    repo.held!.complete();
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });
}
