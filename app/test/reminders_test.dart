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

import 'support/fake_reminders.dart';

void main() {
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
    await pump(tester, repo, const ReminderToggle());
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
