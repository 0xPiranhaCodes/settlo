import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:settlo_core/settlo_core.dart';
import 'package:settlo_settle/src/settle_sheet.dart';
import 'package:url_launcher/url_launcher.dart';

/// Your spaces with their balances, reloaded whenever
/// [ledgerRevisionProvider] is bumped, such as by a recorded settle-up.
final FutureProvider<List<SpaceSummary>> settleSpacesProvider =
    FutureProvider.autoDispose<List<SpaceSummary>>((ref) {
      ref.watch(ledgerRevisionProvider);
      return ref.watch(spacesRepositoryProvider).load();
    });

/// Opens a link in another app: a UPI app through the OS chooser, or
/// WhatsApp. False when nothing on the phone can open it. Tests override
/// this.
final openUrlProvider = Provider<Future<bool> Function(Uri)>(
  (ref) =>
      (uri) => launchUrl(uri, mode: LaunchMode.externalApplication),
);

/// A payment that involves you, with the space it settles.
typedef _Owed = ({SpaceSummary space, Payment<SpaceMember> payment});

List<_Owed> _yours(List<SpaceSummary> spaces, String? spaceId) => [
  for (final s in spaces)
    if (spaceId == null || s.id == spaceId)
      for (final p in s.payments)
        if (p.from.isYou || p.to.isYou) (space: s, payment: p),
];

/// Settle up (Settle artboard). With [memberId] it is the request side:
/// they pay you (canvas note n22). Without, it lists the simplified
/// payments that involve you, in [spaceId] or across your spaces.
class SettleScreen extends ConsumerWidget {
  /// Settle up in [spaceId] (all spaces when null), with [memberId].
  const new({this.spaceId, this.memberId, super.key});

  /// The space it was opened from, if any.
  final String? spaceId;

  /// Who pays you, for the request side.
  final String? memberId;

  @override
  Widget build(BuildContext context, WidgetRef ref) =>
      _SettleRoute(spaceId: spaceId, memberId: memberId, youPay: false);
}

/// Settle up, the side that pays (SettlePay artboard, canvas note n44):
/// what you owe [memberId] in [spaceId], paid through a UPI app.
class SettlePayScreen extends ConsumerWidget {
  /// Paying [memberId] in [spaceId].
  const new({this.spaceId, this.memberId, super.key});

  /// The space the debt is in.
  final String? spaceId;

  /// Who you pay.
  final String? memberId;

  @override
  Widget build(BuildContext context, WidgetRef ref) =>
      _SettleRoute(spaceId: spaceId, memberId: memberId, youPay: true);
}

class _SettleRoute extends ConsumerWidget {
  const new({
    required this.spaceId,
    required this.memberId,
    required this.youPay,
  });

  final String? spaceId;
  final String? memberId;
  final bool youPay;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final spaces = ref.watch(settleSpacesProvider);
    final media = MediaQuery.of(context);
    void close() =>
        context.canPop() ? context.pop() : context.go(SettloRoutes.home);
    final list = spaces.value;
    final owed = list == null ? null : _yours(list, spaceId);
    final match = owed
        ?.where(
          (o) => youPay
              ? o.payment.from.isYou && o.payment.to.id == memberId
              : o.payment.to.isYou && o.payment.from.id == memberId,
        )
        .firstOrNull;
    return Padding(
      padding: EdgeInsets.only(
        top: math.max(54, media.padding.top),
        bottom: media.viewInsets.bottom,
      ),
      child: Material(
        type: MaterialType.transparency,
        child: switch ((owed, match)) {
          (_, final o?) => SettleSheet(
            space: o.space,
            payment: o.payment,
            onClose: close,
          ),
          (null, _) when spaces.hasError => _Frame(
            onClose: close,
            message:
                "We couldn't load your balances. Check your connection and "
                'try again.',
            action: SPrimaryButton(
              label: 'Try again',
              onPressed: () => ref.invalidate(settleSpacesProvider),
            ),
          ),
          (null, _) => _Frame(onClose: close),
          (final owed?, null) when memberId != null || owed.isEmpty => _Frame(
            onClose: close,
            message: owed.isEmpty
                ? "You're all settled up."
                : "You're settled up with them.",
          ),
          (final owed?, null) => _Frame(
            onClose: close,
            label: owed.length == 1 ? '1 PAYMENT' : '${owed.length} PAYMENTS',
            children: [for (final o in owed) _PaymentRow(o)],
          ),
        },
      ),
    );
  }
}

/// The sheet's frame without an amount: handle, close and title, then
/// [children] or [message] and [action].
class _Frame extends StatelessWidget {
  const new({
    required this.onClose,
    this.label,
    this.message,
    this.action,
    this.children = const [],
  });

  final VoidCallback onClose;
  final String? label;
  final String? message;
  final Widget? action;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final c = SettloColors.of(context);
    return DecoratedBox(
      decoration: BoxDecoration(
        color: c.surface,
        border: Border(top: BorderSide(color: c.specular)),
        borderRadius: const BorderRadius.vertical(
          top: Radius.circular(SettloRadius.cardHero),
        ),
      ),
      child: SafeArea(
        top: false,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(
            SettloSpacing.screenMargin,
            20,
            SettloSpacing.screenMargin,
            26,
          ),
          children: [
            Row(
              children: [
                Transform.translate(
                  offset: const Offset(-12, 0),
                  child: IconButton(
                    tooltip: 'Close',
                    onPressed: onClose,
                    icon: SizedBox.square(
                      dimension: 24,
                      child: CustomPaint(
                        painter: SettleGlyph.close(c.textPrimary),
                      ),
                    ),
                  ),
                ),
                Expanded(
                  child: Text(
                    'Settle up',
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.titleSmall,
                  ),
                ),
                const SizedBox(width: SettloSpacing.minTouchTarget - 12),
              ],
            ),
            const SizedBox(height: 22),
            if (label case final label?) ...[
              Text(
                label,
                style: SettloTypography.figtree(
                  12,
                  letterSpacing: 0.3,
                  color: c.textSecondary,
                ),
              ),
              const SizedBox(height: SettloSpacing.x1),
            ],
            ...children,
            if (message case final message?) ...[
              Text(
                message,
                style: SettloTypography.figtree(15, color: c.textPrimary),
              ),
              const SizedBox(height: SettloSpacing.x3),
            ],
            ?action,
          ],
        ),
      ),
    );
  }
}

/// `You pay Kabir · Goa trip  ₹3,650`; opens the pay or request side.
class _PaymentRow extends StatelessWidget {
  const new(this.owed);

  final _Owed owed;

  @override
  Widget build(BuildContext context) {
    final c = SettloColors.of(context);
    final (:space, :payment) = owed;
    final youPay = payment.from.isYou;
    final other = youPay ? payment.to : payment.from;
    return SPressable(
      onTap: () => context.push(
        youPay
            ? SettloRoutes.settlePayTo(space.id, other.id)
            : SettloRoutes.settleWith(space.id, memberId: other.id),
      ),
      ringRadius: BorderRadius.circular(SettloRadius.button),
      child: Container(
        constraints: const BoxConstraints(
          minHeight: SettloSpacing.minTouchTarget,
        ),
        padding: const EdgeInsets.symmetric(vertical: 12),
        decoration: BoxDecoration(
          border: Border(bottom: BorderSide(color: c.hairline)),
        ),
        child: Row(
          children: [
            SAvatar(other.name, size: 32),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    youPay ? 'You pay ${other.name}' : '${other.name} pays you',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: SettloTypography.figtree(15, color: c.textPrimary),
                  ),
                  Text(
                    space.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: SettloTypography.figtree(13, color: c.textSecondary),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 12),
            MoneyText(
              payment.amount,
              tone: youPay ? MoneyTone.youOwe : MoneyTone.owedToYou,
            ),
          ],
        ),
      ),
    );
  }
}
