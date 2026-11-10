import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:settlo_auth/src/widgets.dart';
import 'package:settlo_core/settlo_core.dart';

/// Placeholder for the Splash artboard.
class SplashScreen extends StatelessWidget {
  /// The splash screen.
  const new({super.key});

  @override
  Widget build(BuildContext context) =>
      const SPlaceholderScreen(title: 'Splash', artboard: 'Splash');
}

/// Invitee · Join (canvas note n43). A bearer sees trust copy only, never
/// amounts, until the targeted number is verified.
class JoinScreen extends ConsumerStatefulWidget {
  /// Opens the invite identified by [token].
  const new({required this.token, super.key});

  /// The bearer capability from the incoming link.
  final String token;

  @override
  ConsumerState<JoinScreen> createState() => _JoinScreenState();
}

class _JoinScreenState extends ConsumerState<JoinScreen> {
  late final Future<InvitePreview?> _preview = ref
      .read(invitesRepositoryProvider)
      .inspect(widget.token);
  bool _busy = false;
  String? _error;

  Future<void> _join() async {
    // Disabled state paints next frame, so guard taps queued in this frame.
    if (_busy) return;
    _busy = true;
    if (ref.read(sessionProvider) == null) {
      ref
          .read(pendingInviteTokenProvider.notifier)
          .remember(widget.token, idempotencyKey: newIdempotencyKey());
      if (mounted) context.go(SettloRoutes.phone);
      return;
    }
    if (mounted) setState(() => _error = null);
    try {
      await ref
          .read(invitesRepositoryProvider)
          .redeem(widget.token, idempotencyKey: newIdempotencyKey());
      ref.read(pendingInviteTokenProvider.notifier).clear();
      if (mounted) context.go(SettloRoutes.home);
    } on Exception {
      if (mounted) {
        setState(() {
          _busy = false;
          _error = "This invite couldn't be used. It may have expired.";
        });
      }
    }
  }

  Future<void> _decline() async {
    if (_busy) return;
    _busy = true;
    if (mounted) setState(() => _error = null);
    try {
      await ref.read(invitesRepositoryProvider).decline(widget.token);
      if (mounted) {
        context.go(
          ref.read(sessionProvider) == null
              ? SettloRoutes.welcome
              : SettloRoutes.home,
        );
      }
    } on Exception {
      if (mounted) {
        setState(() {
          _busy = false;
          _error = "This invite couldn't be declined. Try again.";
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) => FutureBuilder<InvitePreview?>(
    future: _preview,
    builder: (context, snapshot) {
      if (snapshot.connectionState != ConnectionState.done) {
        return const Scaffold(body: Center(child: CircularProgressIndicator()));
      }
      final invite = snapshot.data;
      if (invite == null || snapshot.hasError) {
        return Scaffold(
          body: Center(
            child: Text(
              'This invite is no longer available.',
              style: SettloTypography.figtree(
                18,
                color: SettloColors.of(context).textPrimary,
              ),
            ),
          ),
        );
      }
      return _JoinContent(
        invite: invite,
        busy: _busy,
        error: _error,
        onJoin: _join,
        onDecline: _decline,
      );
    },
  );
}

class _JoinContent extends StatelessWidget {
  const new({
    required this.invite,
    required this.busy,
    required this.error,
    required this.onJoin,
    required this.onDecline,
  });

  final InvitePreview invite;
  final bool busy;
  final String? error;
  final VoidCallback onJoin;
  final VoidCallback onDecline;

  @override
  Widget build(BuildContext context) {
    final c = SettloColors.of(context);
    final media = MediaQuery.of(context);
    final space = invite.kind == 'space';
    return Scaffold(
      body: Padding(
        padding: EdgeInsets.fromLTRB(
          24,
          math.max(media.padding.top, 44) + 26,
          24,
          media.padding.bottom + 14,
        ),
        child: LayoutBuilder(
          builder: (context, constraints) => SingleChildScrollView(
            child: ConstrainedBox(
              constraints: BoxConstraints(minHeight: constraints.maxHeight),
              child: IntrinsicHeight(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Semantics(
                      label: 'Settlo',
                      child: Row(
                        children: [
                          const SettloMark(semanticsLabel: null),
                          const SizedBox(width: 8),
                          Text(
                            'settlo',
                            style: SettloTypography.figtree(
                              22,
                              weight: FontWeight.w500,
                              letterSpacing: -0.6,
                              color: c.textPrimary,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 36),
                    Row(
                      children: [
                        SAvatar(invite.inviterName, size: 56),
                        Transform.translate(
                          offset: const Offset(-12, 0),
                          child: SAvatar(space ? 'You' : 'Loan', size: 56),
                        ),
                      ],
                    ),
                    const SizedBox(height: 22),
                    Semantics(
                      header: true,
                      child: Text(
                        '${invite.inviterName} added you to '
                        '${invite.subjectName}',
                        style: SettloTypography.figtree(
                          30,
                          weight: FontWeight.w500,
                          letterSpacing: -0.8,
                          color: c.textPrimary,
                        ).copyWith(height: 1.15),
                      ),
                    ),
                    const SizedBox(height: 10),
                    Text(
                      space
                          ? 'A shared ledger. Everyone sees what is '
                                'recorded, and nothing is yours until you '
                                'confirm it.'
                          : 'A shared record between two people. No amount '
                                'is shown until you verify the invited number.',
                      style: SettloTypography.figtree(
                        15,
                        color: c.textSecondary,
                      ).copyWith(height: 1.5),
                    ),
                    const SizedBox(height: 24),
                    SCard(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 20,
                        vertical: 12,
                      ),
                      child: _FactRow(
                        label: 'Recorded for',
                        value: invite.maskedPhone,
                      ),
                    ),
                    if (error case final message?) ...[
                      const SizedBox(height: 12),
                      Text(
                        message,
                        textAlign: TextAlign.center,
                        style: SettloTypography.figtree(
                          13,
                          color: Theme.of(context).colorScheme.error,
                        ),
                      ),
                    ],
                    const Spacer(),
                    AuthButton(
                      label: 'Verify my number to see the ledger',
                      arrow: true,
                      onPressed: busy ? null : onJoin,
                    ),
                    const SizedBox(height: 10),
                    SSecondaryButton(
                      label: "This isn't me",
                      onPressed: busy ? null : onDecline,
                    ),
                    const SizedBox(height: 16),
                    Text(
                      'Settlo is a shared record. It is not a lender, holds '
                      'no money, and shows balances only to the people '
                      'in them.',
                      textAlign: TextAlign.center,
                      style: SettloTypography.figtree(
                        12,
                        color: c.textMuted,
                      ).copyWith(height: 1.5),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _FactRow extends StatelessWidget {
  const new({required this.label, required this.value});
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final c = SettloColors.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        children: [
          Expanded(
            child: Text(
              label,
              style: SettloTypography.figtree(14, color: c.textSecondary),
            ),
          ),
          Text(
            value,
            style: SettloTypography.figtree(14, color: c.textPrimary),
          ),
        ],
      ),
    );
  }
}
