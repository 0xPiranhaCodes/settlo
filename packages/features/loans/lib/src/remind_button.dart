import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:settlo_core/settlo_core.dart';
import 'package:settlo_core/supabase/reminders.dart';

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
  DateTime? _next;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  Future<void> _load() async {
    try {
      _next = await ref
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
    final delay = _next?.difference(DateTime.now());
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
      final next = await repository.remind(widget.loanId);
      if (!mounted ||
          !identical(repository, ref.read(reminderRepositoryProvider))) {
        return;
      }
      setState(() => _next = next);
      _expire();
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
    final cooling = _next?.isAfter(DateTime.now()) ?? false;
    return Column(
      children: [
        SSecondaryButton(
          label: _busy
              ? 'Please wait…'
              : cooling
              ? 'Reminder sent'
              : 'Remind',
          onPressed: _busy || cooling ? null : _send,
        ),
        if (cooling || _error != null)
          Padding(
            padding: const EdgeInsets.only(top: SettloSpacing.x1),
            child: Text(
              _error ?? 'You can remind again after 24 hours.',
              style: SettloTypography.footnote(
                color: SettloColors.of(context).textSecondary,
              ),
            ),
          ),
      ],
    );
  }
}
