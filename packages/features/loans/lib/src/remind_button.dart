import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:settlo_core/settlo_core.dart';
import 'package:settlo_core/supabase/reminders.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// A server-limited nudge with explicit loading, cooldown and retry states.
class RemindButton extends ConsumerStatefulWidget {
  /// Reminds the other accepted party of [loanId].
  const new({required this.loanId, super.key});

  /// The loan whose server cooldown applies to both parties.
  final String loanId;

  @override
  ConsumerState<RemindButton> createState() => _RemindButtonState();
}

class _RemindButtonState extends ConsumerState<RemindButton> {
  bool _busy = true;
  String? _error;
  ReminderCooldown? _cooldown;
  bool _unavailable = false;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  Future<void> _load() async {
    try {
      _cooldown = await ref
          .read(reminderRepositoryProvider)
          .nextAllowed(widget.loanId);
    } on Exception {
      _error = "Couldn't check reminders. Try again.";
    }
    if (!mounted) return;
    setState(() => _busy = false);
    _expire();
  }

  void _expire() {
    _timer?.cancel();
    final delay = _cooldown?.next.difference(DateTime.now());
    if (delay != null && !delay.isNegative) {
      _timer = Timer(delay, () {
        if (mounted) setState(() {});
      });
    }
  }

  Future<void> _send() async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    final repository = ref.read(reminderRepositoryProvider);
    try {
      // No permission prompt: Remind notifies the other person (#259).
      await repository.remind(widget.loanId);
      final cooldown = await repository.nextAllowed(widget.loanId);
      if (!mounted ||
          !identical(repository, ref.read(reminderRepositoryProvider))) {
        return;
      }
      setState(() => _cooldown = cooldown);
      _expire();
    } on PostgrestException catch (error) {
      if (mounted) {
        setState(() {
          _unavailable = error.code == '22023';
          _error = _unavailable
              ? 'Reminders aren’t available for this loan yet.'
              : "Couldn't send a reminder. Please try again.";
        });
      }
    } on Exception {
      if (mounted) {
        setState(() => _error = "Couldn't send a reminder. Please try again.");
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final cooling = _cooldown?.next.isAfter(DateTime.now()) ?? false;
    return Column(
      children: [
        SSecondaryButton(
          label: _busy
              ? 'Please wait…'
              : cooling
              ? (_cooldown!.sentByYou ? 'Reminder sent' : 'Reminded recently')
              : 'Remind',
          onPressed: _busy || cooling || _unavailable ? null : _send,
        ),
        if (cooling || _error != null)
          Padding(
            padding: const EdgeInsets.only(top: SettloSpacing.x1),
            child: Text(
              _error ?? 'You can remind again when the 24-hour cooldown ends.',
              style: SettloTypography.footnote(
                color: SettloColors.of(context).textSecondary,
              ),
            ),
          ),
      ],
    );
  }
}
