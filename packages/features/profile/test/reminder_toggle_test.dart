import 'dart:async';

import 'package:flutter/material.dart';
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
  Future<DateTime?> nextAllowed(String loanId) async => null;
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
