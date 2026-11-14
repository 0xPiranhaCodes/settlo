import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:settlo_core/settlo_core.dart';
import 'package:settlo_core/supabase/reminders.dart';
import 'package:settlo_platform/src/reminders.dart';

/// Each meaningful context gets at most one explanation per installation.
enum ReminderPermissionTrigger {
  /// A deliberate manual nudge. Unused since #259: Remind notifies the other
  /// person. Kept because the native side stores claims by name.
  remind,

  /// Creating or accepting a scheduled loan.
  instalmentLoan,

  /// Turning the reminder setting on.
  profile,
}

const _title = 'Get reminder notifications?';
const _message =
    'SabkiJeb can notify you about loan nudges and missed instalments. '
    'Names and amounts stay off your lock screen.';

/// Reuses the same explanation and guards navigation and account changes.
Future<void> showReminderPermission(
  BuildContext context,
  WidgetRef ref,
  ReminderPermissionTrigger trigger,
) async {
  final notifications = ref.read(reminderNotificationsProvider);
  if (await notifications.permissionStatus() != 'notDetermined' ||
      !context.mounted) {
    return;
  }
  final repository = ref.read(reminderRepositoryProvider);
  bool active() =>
      context.mounted &&
      identical(repository, ref.read(reminderRepositoryProvider));
  await notifications.promptInContext(
    trigger,
    enabled: repository.enabled,
    active: active,
    explain: () async =>
        await (Theme.of(context).platform == TargetPlatform.iOS
            ? showSettloAlert(
                context: context,
                title: _title,
                message: _message,
                destructive: 'Continue',
                cancel: 'Not now',
                danger: false,
              )
            : showDialog<bool>(
                context: context,
                builder: (context) => AlertDialog(
                  title: const Text(_title),
                  content: const Text(_message),
                  actions: [
                    TextButton(
                      onPressed: () => Navigator.pop(context, false),
                      child: const Text('Not now'),
                    ),
                    TextButton(
                      onPressed: () => Navigator.pop(context, true),
                      child: const Text('Continue'),
                    ),
                  ],
                ),
              )) ??
        false,
  );
  if (active()) ref.invalidate(remindersEnabledProvider);
}

/// Live snapshots are necessary here: invite redemption bypasses the offline
/// mirror, which can still contain the pre-acceptance loan set.
final acceptedLoanSnapshotProvider = Provider<Future<LoansData> Function()>((
  ref,
) {
  final user = ref.watch(sessionProvider)?.user.id;
  final client = ref.watch(supabaseClientProvider);
  return SupabaseLoansRepository(client, userId: user ?? '').load;
});

/// In-memory acceptance events only: a cold launch never produces an event.
final acceptedLoanReminderProvider =
    NotifierProvider<AcceptedLoanReminder, String?>(AcceptedLoanReminder.new);

/// Carries a successful acceptance to a mounted navigation surface.
class AcceptedLoanReminder extends Notifier<String?> {
  @override
  String? build() => null;

  /// Clears an event after the UI takes responsibility for it.
  void clear() => state = null;

  /// Compares accepted loans around redemption, without changing its outcome.
  Future<void> redeem(Future<void> Function() action) async {
    final user = ref.read(sessionProvider)?.user.id;
    if (user == null) return await action();
    LoansData? before;
    try {
      before = await ref.read(acceptedLoanSnapshotProvider)();
    } on Object {
      // Missing/offline snapshots cannot prove a newly accepted loan.
    }
    if (!ref.mounted || ref.read(sessionProvider)?.user.id != user) {
      throw const SessionEnded();
    }
    await action();
    if (before == null || !ref.mounted) return;
    try {
      if (ref.read(sessionProvider)?.user.id != user) return;
      final after = await ref.read(acceptedLoanSnapshotProvider)();
      if (!ref.mounted || ref.read(sessionProvider)?.user.id != user) return;
      final ids = before.loans.map((loan) => loan.id).toSet();
      if (after.loans.any(
        (loan) => !ids.contains(loan.id) && loan.installment != null,
      )) {
        state = user;
      }
    } on Object {
      // The acceptance is already committed; don't turn this into a retry.
    }
  }
}

/// Handles only acceptance events from this running app, under the navigator.
class AcceptedLoanReminderPrompt extends ConsumerWidget {
  /// Wraps the signed-in navigation shell.
  const new({required this.child, super.key});

  /// The navigation surface beneath the permission explanation.
  final Widget child;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final acceptance = ref.watch(acceptedLoanReminderProvider);
    if (acceptance != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) async {
        if (!context.mounted ||
            ref.read(acceptedLoanReminderProvider) != acceptance) {
          return;
        }
        ref.read(acceptedLoanReminderProvider.notifier).clear();
        if (ref.read(sessionProvider)?.user.id == acceptance) {
          await showReminderPermission(
            context,
            ref,
            ReminderPermissionTrigger.instalmentLoan,
          );
        }
      });
    }
    return child;
  }
}
