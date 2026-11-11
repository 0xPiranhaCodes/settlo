import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:settlo_core/settlo_core.dart';
import 'package:settlo_core/supabase/reminders.dart';
import 'package:settlo_platform/src/reminder_permission.dart';

/// Remote delivery remains off until an owner supplies a transport and
/// credentials.
const remoteRemindersEnabled = bool.fromEnvironment('SETTLO_REMOTE_REMINDERS');

/// Credentials-free seam for a future APNs/FCM installation registration.
abstract interface class RemoteReminderTransport {
  /// Registers only while the signed-in user has reminders enabled.
  Future<void> setEnabled({required bool enabled});
}

/// No remote transport is installed in this build.
final remoteReminderTransportProvider = Provider<RemoteReminderTransport?>(
  (ref) => null,
);

/// A privacy-safe notification, with a stable identifier and an absolute
/// instant.
typedef LocalReminder = ({String id, DateTime at, String body});

/// Unpaid instalments fire at 09:00 Asia/Kolkata the following day.
/// Payment updates replace the entire pending set. Local delivery uses the
/// latest synced state; an offline device cannot see payments made elsewhere.
List<LocalReminder> scheduleReminders(
  Iterable<Loan> loans, {
  required bool enabled,
  required DateTime now,
}) {
  if (!enabled) return [];
  final result = <LocalReminder>[];
  for (final loan in loans) {
    final amount = loan.installment?.value;
    final day = loan.dueDay;
    if (loan.closed || loan.youLent || amount == null || day == null) continue;
    final total = (loan.principal.value + amount - 1) ~/ amount;
    final india = now.toUtc().add(const Duration(hours: 5, minutes: 30));
    final month =
        (india.year - loan.startOn.year) * 12 +
        india.month -
        loan.startOn.month;
    final first = math.max(1, math.max(month, loan.repaid.value ~/ amount + 1));
    for (var k = first; k <= total && k < math.max(1, month) + 49; k++) {
      final expected = (k * amount).clamp(0, loan.principal.value);
      if (loan.repaid.value >= expected) continue;
      final due = DateTime.utc(loan.startOn.year, loan.startOn.month + k, day);
      final at = due.add(const Duration(days: 1, hours: 3, minutes: 30));
      if (!at.isAfter(now)) continue;
      result.add((
        id: 'due:${loan.id}:$k',
        at: at,
        body:
            'An instalment was due yesterday. '
            'Please check your loan when you can.',
      ));
    }
  }
  result.sort((a, b) => a.at.compareTo(b.at));
  // Leave room within iOS's pending-notification limit for incoming nudges.
  return result.take(48).toList();
}

/// Serializes native writes so a late fetch cannot restore a signed-out
/// user's reminders.
class ReminderNotifications {
  /// Injectable native channel.
  new({this.channel = const MethodChannel('app.settlo/reminders')});

  /// iOS implementation; other platforms safely no-op for now.
  final MethodChannel channel;
  Future<void> _tail = Future<void>.value();
  int _generation = 0;

  /// Whether iOS has not yet asked for notification permission.
  Future<bool> permissionNeeded() async {
    try {
      return await channel.invokeMethod<bool>('permissionNeeded') ?? false;
    } on MissingPluginException {
      return false;
    } on PlatformException {
      return false;
    }
  }

  /// Called only after an explained, explicit user action.
  Future<void> requestPermission() => _call('requestPermission', null);

  /// Current OS permission; unavailable platforms never prompt.
  Future<String> permissionStatus() async =>
      await _query<String>('permissionStatus') ?? 'unavailable';

  /// Atomically persists this context before displaying its explanation.
  Future<bool> claimPrompt(ReminderPermissionTrigger trigger) async =>
      await _query<bool>('claimPrompt', trigger.name) ?? false;

  Future<T?> _query<T>(String method, [Object? arguments]) async {
    try {
      return await channel.invokeMethod<T>(method, arguments);
    } on MissingPluginException {
      return null;
    } on PlatformException {
      return null;
    }
  }

  /// Opens this app's OS settings after permission has been denied.
  Future<void> openSettings() => _call('openSettings', null);

  bool _prompting = false;

  /// Serializes contextual prompts and never requests after a known answer.
  Future<void> promptInContext(
    ReminderPermissionTrigger trigger, {
    required Future<bool> Function() enabled,
    required Future<bool> Function() explain,
    required bool Function() active,
  }) async {
    if (_prompting) return;
    _prompting = true;
    try {
      if (!await enabled() || !active()) return;
      if (await permissionStatus() != 'notDetermined' || !active()) return;
      if (!await claimPrompt(trigger) || !active()) return;
      if (!await explain() || !active()) return;
      if (!await enabled() || !active()) return;
      if (await permissionStatus() == 'notDetermined' && active()) {
        await requestPermission();
      }
    } on Exception {
      // Permission UX must never fail a loan operation or a preference save.
    } finally {
      _prompting = false;
    }
  }

  /// Changes ownership; the same user keeps native state across restarts.
  Future<void> setOwner(String? userId) {
    ++_generation;
    return _tail = _tail.then((_) => _call('owner', userId));
  }

  /// Replaces reminders owned by Settlo, never another notification surface.
  Future<void> replace(List<LocalReminder> reminders) {
    final generation = ++_generation;
    return _tail = _tail.then((_) async {
      if (generation != _generation) return;
      await _call('replace', [
        for (final r in reminders)
          {'id': r.id, 'at': r.at.millisecondsSinceEpoch, 'body': r.body},
      ]);
    });
  }

  Future<void> _call(String method, Object? arguments) async {
    try {
      await channel.invokeMethod<void>(method, arguments);
    } on MissingPluginException {
      // iOS first; no plugin or credentials required to build Android.
    } on PlatformException {
      // OS permission failures must not interrupt ledger sync.
    }
  }
}

/// Shared native writer survives provider rebuilds and account switches.
final Provider<ReminderNotifications> reminderNotificationsProvider = Provider(
  (ref) => ReminderNotifications(),
);

/// Refreshes on resume, ledger updates and preference changes, and clears
/// on logout.
final reminderSyncProvider = Provider<void>((ref) {
  final notifications = ref.watch(reminderNotificationsProvider);
  final user = ref.watch(sessionProvider.select((s) => s?.user.id));
  var alive = true;
  var revision = 0;
  ref.onDispose(() {
    alive = false;
  });
  unawaited(notifications.setOwner(user));
  if (user == null) return;
  final repository = ref.watch(reminderRepositoryProvider);
  final client = ref.watch(supabaseClientProvider);
  final remote = ref.watch(remoteReminderTransportProvider);
  Future<void> refresh() async {
    final request = ++revision;
    try {
      final enabled = await repository.enabled();
      if (!alive || request != revision) return;
      if (remoteRemindersEnabled) await remote?.setEnabled(enabled: enabled);
      if (!enabled) {
        await notifications.replace([]);
        return;
      }
      final data = await SupabaseLoansRepository(client, userId: user).load();
      final feed = await SupabaseActivityRepository(client).feed(limit: 100);
      if (!alive || request != revision) return;
      final now = DateTime.now().toUtc();
      await notifications.replace([
        ...scheduleReminders(data.loans, enabled: enabled, now: now),
        for (final e
            in feed.where((e) => e.action == ActivityAction.reminded).take(16))
          if (e.action == ActivityAction.reminded &&
              now.difference(e.at).inHours < 24)
            (
              id: 'manual:${e.id}',
              at: now.add(const Duration(seconds: 2)),
              body:
                  'A gentle reminder to check your loan '
                  'when you have a moment.',
            ),
      ]);
    } on Exception {
      // Keep the last known schedule while offline; the next resume retries.
    }
  }

  final lifecycle = AppLifecycleListener(onResume: () => unawaited(refresh()));
  ref
    ..onDispose(lifecycle.dispose)
    ..listen(ledgerRevisionProvider, (_, _) => unawaited(refresh()))
    ..listen(remindersEnabledProvider, (_, _) => unawaited(refresh()));
  unawaited(refresh());
});
