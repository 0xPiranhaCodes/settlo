import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:settlo_core/settlo_core.dart';
import 'package:settlo_platform/settlo_platform.dart';
import 'package:settlo_settle/src/screens.dart';
import 'package:settlo_settle/src/upi.dart';

/// One simplified [payment] in [space] that involves you. When you pay
/// (SettlePay, n44) the amount is coral and the primary action opens a
/// UPI app; when you are paid (Settle, n22) it is a request. Either way a
/// settle-up is recorded only after you confirm the money moved, with one
/// idempotency key for every retry. When you paid, it counts once the
/// payee confirms it (#78); when you were paid, it counts at once.
class SettleSheet extends ConsumerStatefulWidget {
  /// Settling [payment] in [space].
  const new({
    required this.space,
    required this.payment,
    required this.onClose,
    super.key,
  });

  /// The space the payment settles.
  final SpaceSummary space;

  /// Who pays whom, and how much; one side is you.
  final Payment<SpaceMember> payment;

  /// Closes the sheet; also called once the settle-up is recorded.
  final VoidCallback onClose;

  @override
  ConsumerState<SettleSheet> createState() => _SettleSheetState();
}

class _SettleSheetState extends ConsumerState<SettleSheet> {
  final String _key = newIdempotencyKey();

  /// Asking whether the money moved; nothing is recorded before yes.
  bool _confirming = false;

  /// On the request side, record a payment made outside Settlo instead.
  late bool _cash = widget.payment.to.upiId == null;

  bool _busy = false;

  /// Recorded; the sheet is closing and must not record again.
  bool _recorded = false;
  String? _error;

  Payment<SpaceMember> get _p => widget.payment;
  bool get _youPay => _p.from.isYou;
  SpaceMember get _other => _youPay ? _p.to : _p.from;
  String get _amount => formatInr(_p.amount);

  Future<void> _open(
    Provider<Future<bool> Function(Uri)> opener,
    Uri uri,
    String failure,
  ) async {
    setState(() => _error = null);
    final opened = await ref.read(opener)(uri).catchError((_) => false);
    if (!mounted) return;
    setState(() {
      if (!opened) {
        _error = failure;
      } else if (_youPay) {
        // Shown when you come back from the UPI app.
        _confirming = true;
      }
    });
  }

  void _pay() => _open(
    openUpiProvider,
    upiPayUri(
      payee: _p.to.upiId!,
      name: _p.to.name,
      amount: _p.amount,
      note: 'Settlo: ${widget.space.name}',
    ),
    "There's no UPI app on this phone. Pay ${_p.to.name} another way, "
    'then record it here.',
  );

  void _request() => _open(
    openUrlProvider,
    Uri.https('wa.me', '/${_p.from.phone.replaceAll(RegExp(r'\D'), '')}', {
      'text':
          'Hi ${_p.from.name}, settling up ${widget.space.name}: please pay '
          '$_amount to ${_p.to.upiId} on any UPI app. Sent from Settlo.',
    }),
    "WhatsApp didn't open. You can ask ${_p.from.name} another way.",
  );

  Future<void> _record() async {
    // A second tap can land before the rebuild that disables the button.
    if (_busy || _recorded) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    final ledger = ref.read(ledgerRevisionProvider.notifier);
    try {
      await ref.read(expensesRepositoryProvider).add((
        spaceId: widget.space.id,
        description: 'Settle up',
        category: null,
        amount: _p.amount,
        spentOn: null,
        splitType: SplitType.exact,
        isSettlement: true,
        payers: {_p.from.id: _p.amount},
        splits: [
          (
            memberId: _p.to.id,
            amount: _p.amount,
            percentBp: null,
            shares: null,
          ),
        ],
      ), idempotencyKey: _key);
      _recorded = true;
      ledger.bump();
      widget.onClose();
    } on IdempotencyConflict {
      ledger.bump();
      _error = 'This settle-up was already recorded. Close this to see it.';
    } on SettlementPending {
      ledger.bump();
      _error =
          'A payment to ${_p.to.name} is already waiting for them to '
          'confirm. Close this to see it.';
    } on ExpenseRejected {
      _error =
          "This doesn't match the space any more. Someone may have left. "
          'Close this and check the balances.';
    } on SessionEnded {
      // Signed out mid-tap: the user has left, so there is nothing to say.
    } on Exception {
      _error =
          "We couldn't record it. Check your connection and try again. "
          "It won't be recorded twice.";
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = SettloColors.of(context);
    final text = SettloTypography.subheadline(color: c.textSecondary);
    Widget note(String s) => Text(s, textAlign: TextAlign.center, style: text);
    final ask = _youPay
        ? 'Did you pay ${_other.name} $_amount?'
        : 'Did ${_other.name} pay you $_amount?';
    return SAmountSheet(
      title: 'Settle up · ${widget.space.name}',
      onClose: widget.onClose,
      header: _Parties(from: _p.from, to: _p.to),
      amountLabel: _youPay
          ? 'You pay ${_other.name}'
          : '${_other.name} pays you',
      amount: Semantics(
        label: spokenInr(_p.amount),
        excludeSemantics: true,
        child: Text(
          formatInr(_p.amount).substring(1),
          style: TextStyle(
            color: _youPay ? c.money(MoneyTone.youOwe) : c.textPrimary,
          ),
        ),
      ),
      body: SFormBody(
        children: [
          note(
            _youPay
                ? 'clears your balance in ${widget.space.name}'
                : 'full balance',
          ),
          const SizedBox(height: SettloSpacing.x3),
          if (_confirming)
            Text(
              ask,
              textAlign: TextAlign.center,
              style: SettloTypography.headline(color: c.textPrimary),
            )
          else if (_youPay)
            _Info(
              _p.to.upiId == null
                  ? "${_other.name} hasn't added a UPI ID yet. Pay them "
                        'however you usually do, then record it here.'
                  : 'Opens your UPI app with $_amount to ${_p.to.upiId} '
                        'prefilled. You approve it there.',
            )
          else ...[
            _Option(
              title: 'Request via UPI',
              subtitle: _p.to.upiId == null
                  ? 'Add your UPI ID in Profile to request through UPI.'
                  : 'Ask ${_other.name} on WhatsApp to pay $_amount to '
                        '${_p.to.upiId}',
              selected: !_cash,
              onTap: _p.to.upiId == null
                  ? null
                  : () => setState(() => _cash = false),
            ),
            const SizedBox(height: SettloSpacing.x2),
            _Option(
              title: 'Record cash or bank payment',
              subtitle: 'Already paid outside Settlo',
              selected: _cash,
              onTap: () => setState(() => _cash = true),
            ),
          ],
          if (_error case final error?) ...[
            const SizedBox(height: SettloSpacing.x2),
            Text(
              error,
              textAlign: TextAlign.center,
              style: SettloTypography.subheadline(color: c.textPrimary),
            ),
          ],
        ],
      ),
      action: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          note(
            _youPay
                ? "Settlo doesn't move money. After you pay, ${_other.name} "
                      'confirms and both ledgers update.'
                : "Settlo doesn't move money. Nothing is recorded until you "
                      'confirm the payment arrived.',
          ),
          const SizedBox(height: SettloSpacing.x2),
          ...switch ((_confirming, _youPay)) {
            (true, _) => [
              SPrimaryButton(
                label: _busy
                    ? 'Recording…'
                    : _youPay
                    ? 'Yes, I paid'
                    : 'Yes, ${_other.name} paid',
                onPressed: _busy ? null : _record,
              ),
              const SizedBox(height: SettloSpacing.x2),
              SSecondaryButton(
                label: 'Not yet',
                onPressed: _busy
                    ? null
                    : () => setState(() {
                        _confirming = false;
                        _error = null;
                      }),
              ),
            ],
            (false, true) when _p.to.upiId != null => [
              SPrimaryButton(label: 'Pay $_amount via UPI', onPressed: _pay),
              const SizedBox(height: SettloSpacing.x2),
              SSecondaryButton(
                label: 'I already paid in cash',
                onPressed: () => setState(() => _confirming = true),
              ),
            ],
            (false, true) => [
              SPrimaryButton(
                label: 'Record a cash payment',
                onPressed: () => setState(() => _confirming = true),
              ),
            ],
            (false, false) => [
              SPrimaryButton(
                label: _cash ? 'Record payment' : 'Send request on WhatsApp',
                onPressed: _cash
                    ? () => setState(() => _confirming = true)
                    : _request,
              ),
            ],
          },
        ],
      ),
    );
  }
}

/// `P → S` with names under the avatars.
class _Parties extends StatelessWidget {
  const new({required this.from, required this.to});

  final SpaceMember from;
  final SpaceMember to;

  @override
  Widget build(BuildContext context) {
    final c = SettloColors.of(context);
    Widget person(SpaceMember m) => SizedBox(
      width: 88,
      child: Column(
        children: [
          SAvatar(m.isYou ? 'You' : m.name, size: 60),
          const SizedBox(height: 8),
          Text(
            m.isYou ? 'You' : m.name,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            textAlign: TextAlign.center,
            style: SettloTypography.subheadline(color: c.textPrimary),
          ),
        ],
      ),
    );
    return ExcludeSemantics(
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          person(from),
          Padding(
            padding: const EdgeInsets.only(top: 7),
            child: Container(
              width: 46,
              height: 46,
              decoration: BoxDecoration(
                color: c.surfaceRaised,
                shape: BoxShape.circle,
              ),
              child: CustomPaint(painter: SettleGlyph.arrow(c.textPrimary)),
            ),
          ),
          person(to),
        ],
      ),
    );
  }
}

/// A line of what will happen, on a raised surface.
class _Info extends StatelessWidget {
  const new(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    final c = SettloColors.of(context);
    return Text(text, style: SettloTypography.body(color: c.textSecondary));
  }
}

/// A radio card on the request side; a null [onTap] disables it.
class _Option extends StatelessWidget {
  const new({
    required this.title,
    required this.subtitle,
    required this.selected,
    required this.onTap,
  });

  final String title;
  final String subtitle;
  final bool selected;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final c = SettloColors.of(context);
    final radius = BorderRadius.circular(SettloRadius.button);
    final card = Container(
      constraints: const BoxConstraints(
        minHeight: SettloSpacing.minTouchTarget,
      ),
      padding: const EdgeInsets.symmetric(
        horizontal: 16,
        vertical: SettloSpacing.x2,
      ),
      decoration: BoxDecoration(
        color: c.surfaceRaised,
        borderRadius: radius,
        border: Border.all(
          // Selection is primary text, not gold (ruling on PR #71).
          color: selected ? c.textPrimary : c.hairline,
          width: selected ? 1.5 : 1,
        ),
      ),
      child: Row(
        children: [
          Container(
            width: 20,
            height: 20,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              border: Border.all(
                color: selected ? c.textPrimary : c.textSecondary,
                width: selected ? 6 : 1.5,
              ),
            ),
          ),
          const SizedBox(width: SettloSpacing.x2),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: SettloTypography.headline(
                    color: onTap == null ? c.textSecondary : c.textPrimary,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  subtitle,
                  style: SettloTypography.footnote(color: c.textSecondary),
                ),
              ],
            ),
          ),
        ],
      ),
    );
    return onTap == null
        ? Semantics(enabled: false, child: card)
        : SPressable(
            onTap: onTap,
            ringRadius: radius,
            selected: selected,
            child: card,
          );
  }
}

/// The sheet's line glyphs, stroke 1.6 with round caps in a 24 box,
/// centred: an arrow from payer to payee, or the close cross.
class SettleGlyph extends CustomPainter {
  /// A right arrow.
  const new arrow(this.color) : cross = false;

  /// An X.
  const new close(this.color) : cross = true;

  /// Stroke colour.
  final Color color;

  /// Whether this is the close cross.
  final bool cross;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = 1.6
      ..strokeCap = StrokeCap.round
      ..style = PaintingStyle.stroke;
    final o = size.center(Offset.zero) - const Offset(12, 12);
    final lines = cross
        ? const [(Offset(6, 6), Offset(18, 18)), (Offset(18, 6), Offset(6, 18))]
        : const [
            (Offset(5, 12), Offset(19, 12)),
            (Offset(13, 6), Offset(19, 12)),
            (Offset(13, 18), Offset(19, 12)),
          ];
    for (final (a, b) in lines) {
      canvas.drawLine(o + a, o + b, paint);
    }
  }

  @override
  bool shouldRepaint(SettleGlyph old) =>
      old.color != color || old.cross != cross;
}
