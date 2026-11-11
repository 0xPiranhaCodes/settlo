import 'dart:async';

import 'package:settlo_core/supabase/reminders.dart';

/// In-memory reminder API for UI tests.
class FakeReminders implements ReminderRepository {
  bool on = true;
  bool fail = false;
  Exception? sendError;
  bool sentByYou = true;
  bool failRead = false;
  int sends = 0;
  DateTime? next;
  Completer<DateTime>? held;
  @override
  Future<bool> enabled() async {
    if (failRead) throw Exception('offline');
    return on;
  }

  @override
  Future<void> setEnabled({required bool enabled}) async {
    if (fail) throw Exception('offline');
    on = enabled;
  }

  @override
  Future<ReminderCooldown?> nextAllowed(String loanId) async {
    if (failRead) throw Exception('offline');
    return next == null ? null : (next: next!, sentByYou: sentByYou);
  }

  @override
  Future<DateTime> remind(String loanId) async {
    sends++;
    if (sendError != null) throw sendError!;
    if (fail) throw Exception('offline');
    next =
        await (held?.future ??
            Future.value(DateTime.now().add(const Duration(hours: 24))));
    return next!;
  }
}
