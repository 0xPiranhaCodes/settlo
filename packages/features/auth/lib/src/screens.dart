import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:settlo_auth/src/phone_number.dart';
import 'package:settlo_auth/src/sign_in_controller.dart';
import 'package:settlo_auth/src/widgets.dart';
import 'package:settlo_core/settlo_core.dart';
import 'package:settlo_platform/settlo_platform.dart';

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
  late final Future<InvitePreview?> _preview = isInviteToken(widget.token)
      ? ref.read(invitesRepositoryProvider).inspect(widget.token)
      : Future.value();
  bool _busy = false;
  String? _error;
  late final String _redeemKey = newIdempotencyKey();
  late final String _declineKey = newIdempotencyKey();

  Future<void> _join() async {
    // Disabled state paints next frame, so guard taps queued in this frame.
    if (_busy) return;
    _busy = true;
    final pendingInviteNotifier = ref.read(pendingInviteTokenProvider.notifier);
    if (ref.read(sessionProvider) == null) {
      pendingInviteNotifier.remember(widget.token, idempotencyKey: _redeemKey);
      if (mounted) context.go(SettloRoutes.phone);
      return;
    }
    final invites = ref.read(invitesRepositoryProvider);
    if (mounted) setState(() => _error = null);
    try {
      await ref
          .read(acceptedLoanReminderProvider.notifier)
          .redeem(
            () => invites.redeem(widget.token, idempotencyKey: _redeemKey),
          );
      pendingInviteNotifier.clear();
      if (mounted) context.go(SettloRoutes.home);
    } on InviteException catch (error) {
      if (mounted) {
        setState(() {
          _busy = false;
          _error = signInErrorForInvite(error.failure).message(Country.india);
        });
      }
    } on Exception {
      if (mounted) {
        setState(() {
          _busy = false;
          _error = SignInError.network.message(Country.india);
        });
      }
    }
  }

  Future<void> _decline() async {
    if (_busy) return;
    _busy = true;
    if (mounted) setState(() => _error = null);
    try {
      await ref
          .read(invitesRepositoryProvider)
          .decline(widget.token, idempotencyKey: _declineKey);
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
        return const Scaffold(
          body: Center(child: CircularProgressIndicator.adaptive()),
        );
      }
      final invite = snapshot.data;
      if (invite == null || snapshot.hasError) {
        return Scaffold(
          body: Center(
            child: Text(
              'This invite is no longer available.',
              style: SettloTypography.title3(
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
      body: SettloScrollScaffold(
        title: 'Invitation',
        slivers: [
          SliverFillRemaining(
            hasScrollBody: false,
            child: Padding(
              padding: EdgeInsets.fromLTRB(
                20,
                0,
                20,
                media.padding.bottom + 24,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
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
                  const SizedBox(height: SettloSpacing.x3),
                  Semantics(
                    header: true,
                    child: Text(
                      '${invite.inviterName} added you to '
                      '${invite.subjectName}',
                      style: SettloTypography.largeTitle(
                        letterSpacing: -0.8,
                        color: c.textPrimary,
                      ).copyWith(height: 1.15),
                    ),
                  ),
                  const SizedBox(height: SettloSpacing.x2),
                  Text(
                    space
                        ? 'A shared ledger. Everyone sees what is '
                              'recorded, and nothing is yours until you '
                              'confirm it.'
                        : 'A shared record between two people. No amount '
                              'is shown until you verify the invited number.',
                    style: SettloTypography.headline(color: c.textSecondary)
                        .copyWith(height: 1.5),
                  ),
                  const SizedBox(height: 24),
                  SCard(
                    padding: const EdgeInsets.all(SettloSpacing.screenMargin),
                    child: _FactRow(
                      label: 'Recorded for',
                      value: invite.maskedPhone,
                    ),
                  ),
                  if (error case final message?) ...[
                    const SizedBox(height: SettloSpacing.x2),
                    Text(
                      message,
                      textAlign: TextAlign.center,
                      style: SettloTypography.subheadline(
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
                  const SizedBox(height: SettloSpacing.x2),
                  SSecondaryButton(
                    label: "This isn't me",
                    onPressed: busy ? null : onDecline,
                  ),
                  const SizedBox(height: 16),
                  Text(
                    'SabkiJeb is a shared record. It is not a lender, holds '
                    'no money, and shows balances only to the people '
                    'in them.',
                    textAlign: TextAlign.center,
                    style: SettloTypography.footnote(color: c.textMuted)
                        .copyWith(height: 1.5),
                  ),
                ],
              ),
            ),
          ),
        ],
        children: [
          Semantics(
            label: 'SabkiJeb',
            child: Row(
              children: [
                const SettloMark(semanticsLabel: null),
                const SizedBox(width: 8),
                Text(
                  'SabkiJeb',
                  style: SettloTypography.title2(
                    letterSpacing: -0.6,
                    color: c.textPrimary,
                  ),
                ),
              ],
            ),
          ),
        ],
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
      child: SResponsiveRow(
        children: [
          Expanded(
            child: Text(
              label,
              style: SettloTypography.body(color: c.textSecondary),
            ),
          ),
          Text(value, style: SettloTypography.body(color: c.textPrimary)),
        ],
      ),
    );
  }
}
