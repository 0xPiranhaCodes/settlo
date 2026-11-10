import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:settlo_core/settlo_core.dart';
import 'package:settlo_loans/src/glyphs.dart';
import 'package:settlo_loans/src/loan_ring.dart';
import 'package:settlo_loans/src/loans_provider.dart';
import 'package:settlo_loans/src/record_repayment_sheet.dart';
import 'package:settlo_loans/src/repayment_decision.dart';
import 'package:settlo_loans/src/statement_button.dart';

/// A loan (Loan artboard, canvas note n20): a ring for progress, three
/// tiles for how much each time, when next and whether it is on track,
/// then the repayments both parties see. A pending repayment shows
/// confirm and dispute inline, under its row, to the party who did not
/// record it.
class LoanDetailScreen extends ConsumerWidget {
  /// The Loan screen for [loanId].
  const new({required this.loanId, super.key});

  /// The loan shown.
  final String loanId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final data = ref.watch(loansProvider).value;
    final loan = data?.loans.where((l) => l.id == loanId).firstOrNull;
    if (data == null || loan == null) return const Scaffold();
    final c = SettloColors.of(context);
    final media = MediaQuery.of(context);
    return Scaffold(
      body: RefreshIndicator(
        onRefresh: () => ref.refresh(loansProvider.future),
        child: ListView(
          padding: EdgeInsets.fromLTRB(
            SettloSpacing.screenMargin,
            math.max(media.padding.top, 44) + 16,
            SettloSpacing.screenMargin,
            media.padding.bottom + SettloSpacing.x2,
          ),
          children: [
            Row(
              children: [
                IconButton(
                  tooltip: 'Back',
                  onPressed: () => context.canPop()
                      ? context.pop()
                      : context.go(SettloRoutes.loans),
                  style: IconButton.styleFrom(
                    fixedSize: const Size.square(SettloSpacing.minTouchTarget),
                    minimumSize: Size.zero,
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    backgroundColor: c.surface,
                    side: BorderSide(color: c.hairline),
                  ),
                  icon: LoanGlyph(LoanGlyph.back, color: c.textPrimary),
                ),
                Expanded(
                  child: Text(
                    'Loan',
                    textAlign: TextAlign.center,
                    style: SettloTypography.figtree(
                      15,
                      weight: FontWeight.w500,
                      color: c.textPrimary,
                    ),
                  ),
                ),
                StatementButton(loan, yourName: data.yourName),
              ],
            ),
            const SizedBox(height: 20),
            _Hero(loan, today: data.today),
            if (!loan.closed) ...[
              const SizedBox(height: 12),
              SPrimaryButton(
                label: 'Record repayment',
                icon: LoanGlyph(
                  LoanGlyph.plus,
                  color: c.onAction,
                  size: 18,
                  stroke: 1.9,
                ),
                onPressed: () => showRecordRepaymentSheet(context, loan),
              ),
            ],
            const SizedBox(height: 18),
            Row(
              children: [
                Text('REPAYMENTS', style: _label(c)),
                const Spacer(),
                Text('BOTH OF YOU SEE THIS', style: _label(c)),
              ],
            ),
            const SizedBox(height: 10),
            SCard(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 4),
              child: loan.repayments.isEmpty
                  ? Padding(
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      child: Text(
                        loan.youLent
                            ? 'Nothing repaid yet. Record a repayment when '
                                  '${loan.counterparty} pays you.'
                            : 'Nothing repaid yet. Record a repayment when '
                                  'you pay ${loan.counterparty}.',
                        style: SettloTypography.figtree(
                          14,
                          color: c.textSecondary,
                        ),
                      ),
                    )
                  : Column(
                      children: [
                        for (final (i, r) in loan.repayments.indexed)
                          RepaymentRow(
                            r,
                            key: ValueKey(r.id),
                            counterparty: loan.counterparty,
                            youLent: loan.youLent,
                            divider: i < loan.repayments.length - 1,
                          ),
                      ],
                    ),
            ),
          ],
        ),
      ),
    );
  }
}

TextStyle _label(SettloColors c) =>
    SettloTypography.figtree(12, letterSpacing: 0.3, color: c.textSecondary);

/// The ring, who and what is outstanding, and the three tiles.
class _Hero extends StatelessWidget {
  const new(this.loan, {required this.today});

  final Loan loan;
  final DateTime today;

  @override
  Widget build(BuildContext context) {
    final c = SettloColors.of(context);
    final small = SettloTypography.figtree(12, color: c.textSecondary);
    const terms = '· interest free';
    return SCard(
      hero: true,
      padding: const EdgeInsets.all(20),
      child: Column(
        children: [
          Row(
            children: [
              LoanRing(loan.progress),
              const SizedBox(width: 18),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        ExcludeSemantics(
                          child: SAvatar(loan.counterparty, size: 24),
                        ),
                        const SizedBox(width: SettloSpacing.x1),
                        Flexible(
                          child: Text(
                            loan.counterparty,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: SettloTypography.figtree(
                              14,
                              color: c.textPrimary,
                            ),
                          ),
                        ),
                        Flexible(
                          child: Text(
                            ' · since ${monthYear(loan.startOn)}',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: small,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 10),
                    Text(
                      loan.youLent ? 'Outstanding' : 'You owe',
                      style: small,
                    ),
                    const SizedBox(height: 2),
                    FittedBox(
                      fit: BoxFit.scaleDown,
                      alignment: Alignment.centerLeft,
                      child: MoneyText(loan.outstanding, size: 32),
                    ),
                    const SizedBox(height: 4),
                    Semantics(
                      label: 'of ${spokenInr(loan.principal)} $terms',
                      excludeSemantics: true,
                      child: Text(
                        'of ${formatInr(loan.principal)} $terms',
                        style: small,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 18),
          IntrinsicHeight(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                for (final (i, tile) in _tiles().indexed) ...[
                  if (i > 0) const SizedBox(width: SettloSpacing.x1),
                  Expanded(child: tile),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  List<_Tile> _tiles() {
    final installment = loan.installment;
    final next = loan.nextDueOn;
    final ends = loan.endsOn;
    return [
      if (installment == null)
        const _Tile('Instalment', 'Flexible', 'any amount')
      else
        _Tile(
          'Instalment',
          formatInr(installment),
          'monthly · ${ordinal(loan.dueDay ?? 1)}',
          spoken: spokenInr(installment),
        ),
      if (next == null)
        _Tile('Next due', loan.closed ? 'None' : 'Any time', 'no schedule')
      else
        _Tile('Next due', dayMonth(next), switch (next.difference(today)) {
          final d when d.inDays <= 0 => 'today',
          final d when d.inDays == 1 => 'tomorrow',
          final d => 'in ${d.inDays} days',
        }),
      _Tile('Schedule', switch (loan.onTrack) {
        _ when loan.closed => 'Repaid',
        true => 'On track',
        false => 'Behind',
        null => 'Flexible',
      }, ends == null ? 'no end date' : 'ends ${monthYear(ends)}'),
    ];
  }
}

/// A stat tile: label, value and a line under it.
class _Tile extends StatelessWidget {
  const new(this.label, this.value, this.detail, {this.spoken});

  final String label;
  final String value;
  final String detail;

  /// [value] as a screen reader should say it, for amounts.
  final String? spoken;

  @override
  Widget build(BuildContext context) {
    final c = SettloColors.of(context);
    final small = SettloTypography.figtree(11, color: c.textSecondary);
    return Semantics(
      label: '$label, ${spoken ?? value}, $detail',
      excludeSemantics: true,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          color: c.surfaceRaised,
          borderRadius: BorderRadius.circular(SettloRadius.button),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(label, style: small),
            const SizedBox(height: 4),
            FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.centerLeft,
              child: Text(
                value,
                style: SettloTypography.figtree(
                  16,
                  weight: FontWeight.w500,
                  color: c.textPrimary,
                ),
              ),
            ),
            const SizedBox(height: 2),
            Text(detail, style: small),
          ],
        ),
      ),
    );
  }
}

/// One repayment: date, how and who confirmed it, and the amount. When
/// it waits for you, confirm and dispute sit under it (n20).
class RepaymentRow extends ConsumerStatefulWidget {
  /// The row for [repayment] on a loan with [counterparty].
  const new(
    this.repayment, {
    required this.counterparty,
    required this.youLent,
    this.divider = true,
    super.key,
  });

  /// The repayment shown.
  final LoanRepayment repayment;

  /// The other party's name.
  final String counterparty;

  /// Whether the viewer lent the money.
  final bool youLent;

  /// Whether a hairline follows the row.
  final bool divider;

  @override
  ConsumerState<RepaymentRow> createState() => _RepaymentRowState();
}

class _RepaymentRowState extends ConsumerState<RepaymentRow> {
  late final RepaymentDecisionController _decision;

  @override
  void initState() {
    super.initState();
    _decision = RepaymentDecisionController(ref, widget.repayment.id)
      ..addListener(_changed);
  }

  void _changed() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _decision
      ..removeListener(_changed)
      ..dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = SettloColors.of(context);
    final r = widget.repayment;
    final who = widget.counterparty;
    final how = r.method?.label ?? 'Repayment';
    final by = r.recordedByYou ? who : 'you';
    final text = SettloTypography.figtree(14, color: c.textPrimary);
    final small = SettloTypography.figtree(13, color: c.textSecondary);
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 12),
      decoration: BoxDecoration(
        border: widget.divider
            ? Border(bottom: BorderSide(color: c.hairline))
            : null,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Semantics(
            button: r.awaitsYou,
            label: r.awaitsYou ? 'Review repayment' : null,
            child: InkWell(
              onTap: r.awaitsYou
                  ? () => context.push(SettloRoutes.confirmRepayment(r.id))
                  : null,
              child: ConstrainedBox(
                constraints: const BoxConstraints(
                  minHeight: SettloSpacing.minTouchTarget,
                ),
                child: Row(
                  children: [
                    SizedBox(
                      width: 44,
                      child: Text(dayMonth(r.paidOn), style: small),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: switch (r.status) {
                        RepaymentStatus.confirmed => Text(
                          '$how · confirmed by $by',
                          style: text,
                        ),
                        RepaymentStatus.disputed => Text(
                          '$how · disputed by $by',
                          style: text.copyWith(color: c.textSecondary),
                        ),
                        RepaymentStatus.pending => Row(
                          children: [
                            Text(how, style: text),
                            const SizedBox(width: SettloSpacing.x1),
                            Flexible(
                              child: _Badge(
                                r.awaitsYou ? 'awaiting you' : 'awaiting $who',
                              ),
                            ),
                          ],
                        ),
                      },
                    ),
                    const SizedBox(width: 12),
                    MoneyText(
                      r.amount,
                      tone: r.status == RepaymentStatus.disputed
                          ? MoneyTone.settled
                          : MoneyTone.neutral,
                    ),
                  ],
                ),
              ),
            ),
          ),
          if (r.disputeReason case final reason?)
            Padding(
              padding: const EdgeInsets.only(left: 56, top: 4),
              child: Text('“$reason”', style: small),
            ),
          if (r.awaitsYou) ...[
            const SizedBox(height: 2),
            Padding(
              padding: const EdgeInsets.only(left: 56),
              child: Wrap(
                spacing: SettloSpacing.x1,
                children: [
                  _Pill(
                    label: _decision.busy
                        ? 'Confirming…'
                        : widget.youLent
                        ? 'Confirm received'
                        : 'Confirm paid',
                    primary: true,
                    onTap: _decision.busy ? null : _decision.confirm,
                  ),
                  _Pill(
                    label: widget.youLent ? "Didn't get it" : "Didn't pay it",
                    onTap: _decision.busy
                        ? null
                        : () => showSettloSheet<void>(
                            context: context,
                            builder: (context) => DisputeSheet(
                              repayment: r,
                              counterparty: who,
                              youLent: widget.youLent,
                              decision: _decision,
                              onClose: () => Navigator.of(context).pop(),
                            ),
                          ),
                  ),
                ],
              ),
            ),
          ],
          if (_decision.error case final error?)
            Padding(
              padding: const EdgeInsets.only(left: 56, top: 4),
              child: Text(
                error,
                style: SettloTypography.figtree(13, color: c.textPrimary),
              ),
            ),
        ],
      ),
    );
  }
}

/// A status tag: outlined in secondary, never gold or green.
class _Badge extends StatelessWidget {
  const new(this.label);

  final String label;

  @override
  Widget build(BuildContext context) {
    final c = SettloColors.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
      decoration: BoxDecoration(
        border: Border.all(color: c.textSecondary),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        label,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: SettloTypography.figtree(
          11,
          color: c.textSecondary,
        ).copyWith(height: 1.3),
      ),
    );
  }
}

/// An inline action: 36 drawn inside a 44 target. [primary] is the
/// action colour; a null [onTap] disables it.
class _Pill extends StatelessWidget {
  const new({required this.label, required this.onTap, this.primary = false});

  final String label;
  final VoidCallback? onTap;
  final bool primary;

  @override
  Widget build(BuildContext context) {
    final c = SettloColors.of(context);
    final pill = ConstrainedBox(
      constraints: const BoxConstraints(
        minHeight: SettloSpacing.minTouchTarget,
        minWidth: SettloSpacing.minTouchTarget,
      ),
      child: Center(
        widthFactor: 1,
        heightFactor: 1,
        child: Container(
          height: 36,
          padding: const EdgeInsets.symmetric(horizontal: 14),
          decoration: ShapeDecoration(
            color: primary ? c.action : null,
            shape: StadiumBorder(
              side: primary
                  ? BorderSide.none
                  : BorderSide(color: c.buttonBorder),
            ),
          ),
          child: Center(
            widthFactor: 1,
            child: Text(
              label,
              style: SettloTypography.figtree(
                13,
                weight: primary ? FontWeight.w500 : FontWeight.w400,
                color: primary ? c.onAction : c.textPrimary,
              ),
            ),
          ),
        ),
      ),
    );
    final tap = onTap;
    return tap == null
        ? Semantics(button: true, enabled: false, child: pill)
        : SPressable(
            onTap: tap,
            ringRadius: BorderRadius.circular(SettloRadius.pill),
            child: pill,
          );
  }
}

/// "Didn't get it": asks why, then disputes the repayment. Final, so it
/// says so. It shares the same busy guard and idempotency state as confirm.
class DisputeSheet extends ConsumerStatefulWidget {
  /// Disputing [repayment], recorded by [counterparty].
  const new({
    required this.repayment,
    required this.counterparty,
    required this.youLent,
    required this.decision,
    required this.onClose,
    super.key,
  });

  /// The pending repayment.
  final LoanRepayment repayment;

  /// Who recorded it.
  final String counterparty;

  /// Whether the viewer lent the money.
  final bool youLent;

  /// The shared decision state for this repayment.
  final RepaymentDecisionController decision;

  /// Closes the sheet; also called once the dispute is saved.
  final VoidCallback onClose;

  @override
  ConsumerState<DisputeSheet> createState() => _DisputeSheetState();
}

class _DisputeSheetState extends ConsumerState<DisputeSheet> {
  final _reason = TextEditingController();

  @override
  void initState() {
    super.initState();
    widget.decision.addListener(_changed);
  }

  void _changed() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    widget.decision.removeListener(_changed);
    _reason.dispose();
    super.dispose();
  }

  Future<void> _send() async {
    if (await widget.decision.dispute(_reason.text)) widget.onClose();
  }

  @override
  Widget build(BuildContext context) {
    final c = SettloColors.of(context);
    final r = widget.repayment;
    final reason = _reason.text.trim();
    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(
          SettloSpacing.screenMargin,
          24,
          SettloSpacing.screenMargin,
          26,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Semantics(
              label: widget.youLent
                  ? "Didn't get ${spokenInr(r.amount)} from "
                        '${widget.counterparty}?'
                  : "Didn't pay ${spokenInr(r.amount)} to "
                        '${widget.counterparty}?',
              excludeSemantics: true,
              child: Text(
                widget.youLent
                    ? "Didn't get ${formatInr(r.amount)} from "
                          '${widget.counterparty}?'
                    : "Didn't pay ${formatInr(r.amount)} to "
                          '${widget.counterparty}?',
                style: SettloTypography.figtree(
                  17,
                  weight: FontWeight.w500,
                  color: c.textPrimary,
                ),
              ),
            ),
            const SizedBox(height: 6),
            Text(
              "Tell ${widget.counterparty} what's wrong. It won't count, and "
              "this can't be undone; they can record a corrected one.",
              style: SettloTypography.figtree(13, color: c.textSecondary),
            ),
            const SizedBox(height: 16),
            Semantics(
              label: 'Reason',
              child: TextField(
                controller: _reason,
                autofocus: true,
                maxLength: 500,
                textCapitalization: TextCapitalization.sentences,
                onChanged: (_) {
                  widget.decision.clearError();
                  setState(() {});
                },
                style: SettloTypography.figtree(15, color: c.textPrimary),
                decoration: InputDecoration(
                  hintText: widget.youLent
                      ? 'Not received yet'
                      : 'Not paid yet',
                  counterText: '',
                ),
              ),
            ),
            if (widget.decision.error case final error?) ...[
              const SizedBox(height: 12),
              Text(
                error,
                style: SettloTypography.figtree(13, color: c.textPrimary),
              ),
            ],
            const SizedBox(height: 16),
            SPrimaryButton(
              label: widget.decision.busy
                  ? 'Sending…'
                  : widget.youLent
                  ? 'Mark as not received'
                  : 'Mark as not paid',
              onPressed: widget.decision.busy || reason.isEmpty ? null : _send,
            ),
            const SizedBox(height: 10),
            SSecondaryButton(
              label: 'Cancel',
              onPressed: widget.decision.busy ? null : widget.onClose,
            ),
          ],
        ),
      ),
    );
  }
}
