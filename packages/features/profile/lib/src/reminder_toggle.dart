import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:settlo_core/settlo_core.dart';
import 'package:settlo_core/supabase/reminders.dart';
import 'package:settlo_platform/settlo_platform.dart';

/// Server-persisted reminder preference, with failed writes left visible.
class ReminderToggle extends ConsumerStatefulWidget {
  /// Profile's Reminders setting.
  const new({super.key});

  @override
  ConsumerState<ReminderToggle> createState() => _ReminderToggleState();
}

class _ReminderToggleState extends ConsumerState<ReminderToggle> {
  bool _busy = false;
  String? _error;
  String? _permission;
  late final AppLifecycleListener _lifecycle;

  @override
  void initState() {
    super.initState();
    _lifecycle = AppLifecycleListener(onResume: () => unawaited(_status()));
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (!mounted) return;
      await showReminderPermission(
        context,
        ref,
        ReminderPermissionTrigger.profile,
      );
      await _status();
    });
  }

  Future<void> _status() async {
    if (!mounted) return;
    final status = await ref
        .read(reminderNotificationsProvider)
        .permissionStatus();
    if (mounted) setState(() => _permission = status);
  }

  @override
  void dispose() {
    _lifecycle.dispose();
    super.dispose();
  }

  Future<void> _save(bool enabled) async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    final repository = ref.read(reminderRepositoryProvider);
    try {
      await repository.setEnabled(enabled: enabled);
      if (!mounted ||
          !identical(repository, ref.read(reminderRepositoryProvider))) {
        return;
      }
      if (enabled) {
        await showReminderPermission(
          context,
          ref,
          ReminderPermissionTrigger.profile,
        );
        await _status();
      }
      if (!mounted ||
          !identical(repository, ref.read(reminderRepositoryProvider))) {
        return;
      }
      ref.invalidate(remindersEnabledProvider);
      await ref.read(remindersEnabledProvider.future);
    } on Exception {
      if (mounted) {
        setState(() => _error = "Couldn't save reminders. Please try again.");
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final enabled = ref.watch(remindersEnabledProvider);
    final c = SettloColors.of(context);
    return SCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Reminders',
                      style: SettloTypography.headline(color: c.textPrimary),
                    ),
                    Text(
                      'Loan nudges and missed instalments',
                      style: SettloTypography.footnote(color: c.textSecondary),
                    ),
                  ],
                ),
              ),
              SizedBox(
                height: SettloSpacing.minTouchTarget,
                child: Semantics(
                  label: 'Reminders',
                  child: Switch.adaptive(
                    value: enabled.value ?? false,
                    onChanged: _busy || enabled.value == null ? null : _save,
                    activeTrackColor: c.action,
                  ),
                ),
              ),
            ],
          ),
          if (_permission == 'denied') ...[
            const Text('Notifications are off in iOS Settings.'),
            TextButton(
              onPressed: () =>
                  ref.read(reminderNotificationsProvider).openSettings(),
              child: const Text('Open Settings'),
            ),
          ],
          if (_error != null || enabled.hasError) ...[
            Text(
              _error ?? "Couldn't load reminders.",
              style: SettloTypography.footnote(color: c.textSecondary),
            ),
            if (enabled.hasError)
              SSecondaryButton(
                label: 'Try again',
                onPressed: () => ref.invalidate(remindersEnabledProvider),
              ),
          ],
        ],
      ),
    );
  }
}
