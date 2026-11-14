import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:settlo_core/settlo_core.dart';
import 'package:settlo_core/supabase/reminders.dart';
import 'package:settlo_loans/src/remind_button.dart';
import 'package:settlo_profile/src/reminder_toggle.dart';
import 'package:settlo_test_support/golden.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'support/fake_notification_permission.dart';
import 'support/fake_reminders.dart';

void main() {
  setUp(() => FakeNotificationPermission('granted').install());
  final capture = GlobalKey();
  Future<void> pump(
    WidgetTester tester,
    FakeReminders repo,
    Widget child, {
    double height = 200,
  }) async {
    await loadSettloFonts();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [reminderRepositoryProvider.overrideWithValue(repo)],
        child: MaterialApp(
          theme: SettloTheme.light(),
          home: Scaffold(
            body: Center(
              child: RepaintBoundary(
                key: capture,
                child: SizedBox(
                  width: 360,
                  height: height,
                  child: ColoredBox(
                    color: SettloTheme.light().scaffoldBackgroundColor,
                    child: Padding(
                      padding: const EdgeInsets.all(20),
                      child: child,
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  for (final permission in ['notDetermined', 'granted', 'denied']) {
    testWidgets('Remind sends without asking for permission: $permission', (
      tester,
    ) async {
      final native = FakeNotificationPermission(permission)..install();
      final repo = FakeReminders();
      await pump(tester, repo, const RemindButton(loanId: 'loan'));
      await tester.tap(find.text('Remind'));
      await tester.pumpAndSettle();
      // Remind notifies the other person, so it never asks (#259).
      expect(find.text('Get reminder notifications?'), findsNothing);
      expect(repo.sends, 1);
      expect(native.calls, isNot(contains('claimPrompt')));
      expect(native.requests, 0);
    });
  }

  Future<void> screenshot(String name) async {
    if (!const bool.fromEnvironment('REMINDER_EVIDENCE')) return;
    final boundary =
        capture.currentContext!.findRenderObject()! as RenderRepaintBoundary;
    final image = await boundary.toImage(pixelRatio: 2);
    final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
    await File('../docs/evidence/107/$name.png')
        .writeAsBytes(bytes!.buffer.asUint8List());
    image.dispose();
  }

  testWidgets('enabled, sending guard, sent and restored cooldown', (
    tester,
  ) async {
    final repo = FakeReminders()..held = Completer<DateTime>();
    await pump(tester, repo, const RemindButton(loanId: 'loan'));
    expect(find.text('Remind'), findsOneWidget);
    await tester.runAsync(() => screenshot('remind-enabled'));
    await tester.tap(find.text('Remind'));
    await tester.tap(find.text('Remind'));
    await tester.pump();
    expect(repo.sends, 1);
    repo.held!.complete(DateTime.now().add(const Duration(hours: 24)));
    await tester.pumpAndSettle();
    expect(find.text('Reminder sent'), findsOneWidget);
    await tester.runAsync(() => screenshot('remind-sent'));
    await tester.pumpWidget(const SizedBox());
    final cooling = FakeReminders()
      ..next = DateTime.now().add(const Duration(hours: 2));
    await pump(tester, cooling, const RemindButton(loanId: 'loan'));
    expect(find.text('Reminder sent'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
  });
  testWidgets('received nudge and losing send never claim you sent it', (
    tester,
  ) async {
    final repo = FakeReminders()
      ..sentByYou = false
      ..next = DateTime.now().add(const Duration(hours: 2));
    await pump(tester, repo, const RemindButton(loanId: 'loan'));
    expect(find.text('Reminded recently'), findsOneWidget);
    expect(find.text('Reminder sent'), findsNothing);
    await tester.tap(find.text('Reminded recently'));
    expect(repo.sends, 0);
    await tester.pumpWidget(const SizedBox());
    repo.next = null;
    await pump(tester, repo, const RemindButton(loanId: 'loan'));
    await tester.tap(find.text('Remind'));
    await tester.pumpAndSettle();
    expect(find.text('Reminded recently'), findsOneWidget);
    expect(find.text('Reminder sent'), findsNothing);
    await tester.pumpWidget(const SizedBox());
  });
  testWidgets('unavailable loan disables Remind with no retry instruction', (
    tester,
  ) async {
    final repo = FakeReminders()
      ..sendError = const PostgrestException(
        message: 'Reminder unavailable',
        code: '22023',
      );
    await pump(tester, repo, const RemindButton(loanId: 'loan'));
    await tester.tap(find.text('Remind'));
    await tester.pumpAndSettle();
    expect(
      find.text('Reminders aren’t available for this loan yet.'),
      findsOneWidget,
    );
    expect(find.textContaining('try again'), findsNothing);
    await tester.tap(find.text('Remind'));
    expect(repo.sends, 1);
    expect(
      tester.widget<SSecondaryButton>(find.byType(SSecondaryButton)).onPressed,
      isNull,
    );
  });
  testWidgets('other server errors remain retryable', (tester) async {
    final repo = FakeReminders()
      ..sendError = const PostgrestException(message: 'Offline', code: '503');
    await pump(tester, repo, const RemindButton(loanId: 'loan'));
    await tester.tap(find.text('Remind'));
    await tester.pumpAndSettle();
    expect(
      find.text("Couldn't send a reminder. Please try again."),
      findsOneWidget,
    );
    expect(
      tester.widget<SSecondaryButton>(find.byType(SSecondaryButton)).onPressed,
      isNotNull,
    );
  });
  testWidgets('send failure is retryable', (tester) async {
    final repo = FakeReminders()..fail = true;
    await pump(tester, repo, const RemindButton(loanId: 'loan'));
    await tester.tap(find.text('Remind'));
    await tester.pumpAndSettle();
    expect(
      find.text("Couldn't send a reminder. Please try again."),
      findsOneWidget,
    );
    await tester.runAsync(() => screenshot('remind-error'));
    repo.fail = false;
    await tester.tap(find.text('Remind'));
    await tester.pumpAndSettle();
    expect(find.text('Reminder sent'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
  });
  testWidgets('toggle persists and a failed write preserves its value', (
    tester,
  ) async {
    final repo = FakeReminders();
    await pump(tester, repo, const ReminderToggle(), height: 260);
    expect(tester.widget<Switch>(find.byType(Switch)).value, isTrue);
    await tester.runAsync(() => screenshot('profile-reminders-on'));
    await tester.tap(find.byType(Switch));
    await tester.pumpAndSettle();
    expect(repo.on, isFalse);
    expect(tester.widget<Switch>(find.byType(Switch)).value, isFalse);
    await tester.runAsync(() => screenshot('profile-reminders-off'));
    repo.fail = true;
    await tester.tap(find.byType(Switch));
    await tester.pumpAndSettle();
    expect(repo.on, isFalse);
    expect(
      find.text("Couldn't save reminders. Please try again."),
      findsOneWidget,
    );
  });
  testWidgets('failed reads show retryable copy for button and preference', (
    tester,
  ) async {
    final repo = FakeReminders()..failRead = true;
    await pump(tester, repo, const RemindButton(loanId: 'loan'));
    expect(find.text("Couldn't check reminders. Try again."), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
    await pump(tester, repo, const ReminderToggle(), height: 260);
    expect(find.text("Couldn't load reminders."), findsOneWidget);
    repo.failRead = false;
    await tester.tap(find.text('Try again'));
    await tester.pumpAndSettle();
    expect(tester.widget<Switch>(find.byType(Switch)).value, isTrue);
  });
}
