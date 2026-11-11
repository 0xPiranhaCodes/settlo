import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:settlo_core/supabase/providers.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Online-only, time-sensitive reminders. Never queued for a later surprise
/// send.
abstract interface class ReminderRepository {
  /// Whether this user accepts reminders (on when no preference exists).
  Future<bool> enabled();

  /// Persists the preference on the server.
  Future<void> setEnabled({required bool enabled});

  /// Next allowed send time, or null before the first reminder.
  Future<DateTime?> nextAllowed(String loanId);

  /// Sends once, or returns the existing 24-hour deadline on a replay.
  Future<DateTime> remind(String loanId);
}

/// The server is the authority for recipient, opt-out and cooldown.
class SupabaseReminderRepository implements ReminderRepository {
  /// Uses the current authenticated client.
  const new(this.client);

  /// Scoped API client.
  final SupabaseClient client;

  @override
  Future<bool> enabled() async {
    final rows = await client.from('reminder_preferences').select('enabled');
    return rows.firstOrNull?['enabled'] as bool? ?? true;
  }

  @override
  Future<void> setEnabled({required bool enabled}) =>
      client.rpc<void>('set_reminders', params: {'p_enabled': enabled});

  @override
  Future<DateTime?> nextAllowed(String loanId) async {
    final rows = await client
        .from('loan_reminders')
        .select('sent_at')
        .eq('loan_id', loanId);
    final at = rows.firstOrNull?['sent_at'] as String?;
    return at == null
        ? null
        : DateTime.parse(at).add(const Duration(hours: 24));
  }

  @override
  Future<DateTime> remind(String loanId) async => DateTime.parse(
    await client.rpc<String>('remind_loan', params: {'p_loan_id': loanId}),
  );
}

/// Injectable reminder API, rebuilt when the account changes.
final reminderRepositoryProvider = Provider<ReminderRepository>((ref) {
  ref.watch(sessionProvider.select((s) => s?.user.id));
  return SupabaseReminderRepository(ref.watch(supabaseClientProvider));
});

/// Persisted preference; callers invalidate after a successful change.
final remindersEnabledProvider = FutureProvider<bool>(
  (ref) => ref.watch(reminderRepositoryProvider).enabled(),
);
