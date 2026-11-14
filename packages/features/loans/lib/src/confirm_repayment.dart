import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:settlo_core/settlo_core.dart';
import 'package:settlo_loans/src/glyphs.dart';
import 'package:settlo_loans/src/loan_detail.dart';
import 'package:settlo_loans/src/loans_provider.dart';
import 'package:settlo_loans/src/repayment_decision.dart';

/// A pending repayment as a checkable receipt (ConfirmRepayment, note n23).
class ConfirmRepaymentScreen extends ConsumerStatefulWidget {
  /// The receipt for [repaymentId].
  const new({required this.repaymentId, super.key});

  /// The repayment to review.
  final String repaymentId;

  @override
  ConsumerState<ConfirmRepaymentScreen> createState() => _ConfirmState();
}

class _ConfirmState extends ConsumerState<ConfirmRepaymentScreen> {
  late final RepaymentDecisionController _decision;

  @override
  void initState() {
    super.initState();
    _decision = RepaymentDecisionController(ref, widget.repaymentId)
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
    final data = ref.watch(loansProvider);
    final found = _find(data.value?.loans ?? const [], widget.repaymentId);
    if (found case (final loan, final repayment)) {
      return _Receipt(loan: loan, repayment: repayment, decision: _decision);
    }
    return _Unavailable(loading: data.isLoading, failed: data.hasError);
  }
}

(Loan, LoanRepayment)? _find(List<Loan> loans, String id) {
  for (final loan in loans) {
    for (final repayment in loan.repayments) {
      if (repayment.id == id) return (loan, repayment);
    }
  }
  return null;
}

class _Unavailable extends StatelessWidget {
  const new({required this.loading, required this.failed});

  final bool loading;
  final bool failed;

  @override
  Widget build(BuildContext context) => Scaffold(
    body: SettloScrollScaffold(
      title: 'Confirm repayment',
      largeTitle: 'Confirm repayment',
      children: [
        _header(context),
        const SizedBox(height: SettloSpacing.x5),
        Text(
          loading
              ? 'Loading…'
              : failed
              ? "We couldn't load this repayment. Try again."
              : 'This repayment is no longer available.',
          textAlign: TextAlign.center,
        ),
      ],
    ),
  );
}

/// The header off iOS; iOS shows the shared navigation bar and glass back.
Widget _header(BuildContext context) {
  final c = SettloColors.of(context);
  return MediaQuery.removePadding(
    context: context,
    removeTop: true,
    child: AppBar(
      primary: false,
      toolbarHeight: 56,
      leadingWidth: 44,
      leading: Center(
        child: IconButton(
          tooltip: 'Back',
          onPressed: context.pop,
          style: IconButton.styleFrom(
            fixedSize: const Size.square(SettloSpacing.minTouchTarget),
            backgroundColor: c.surface,
            side: BorderSide(color: c.hairline),
          ),
          icon: LoanGlyph(LoanGlyph.back, color: c.textPrimary),
        ),
      ),
      title: Text(
        'Confirm',
        style: SettloTypography.headline(color: c.textPrimary),
      ),
      centerTitle: true,
    ),
  );
}

class _Receipt extends StatelessWidget {
  const new({
    required this.loan,
    required this.repayment,
    required this.decision,
  });

  final Loan loan;
  final LoanRepayment repayment;
  final RepaymentDecisionController decision;

  @override
  Widget build(BuildContext context) {
    final c = SettloColors.of(context);
    final canAct = repayment.awaitsYou;
    final after = loan.outstandingAfter(repayment);
    final overpayment =
        repayment.status == RepaymentStatus.pending &&
        repayment.amount.value > loan.outstanding.value;
    final method = repayment.method?.label ?? 'Repayment';
    final reference = repayment.reference?.trim();
    final referenceText = reference == null || reference.isEmpty
        ? ''
        : ' · ref $reference';
    final amount = formatInr(repayment.amount);
    final paidOn = dayMonth(repayment.paidOn);
    final recordedBy = repayment.recordedByYou ? 'You' : loan.counterparty;
    final summary = repayment.recordedByYou
        ? 'You recorded this payment'
        : loan.youLent
        ? '${loan.counterparty} says they paid you'
        : '${loan.counterparty} says you paid $amount';
    final guidance = canAct
        ? loan.youLent
              ? 'Check your bank or UPI app for $amount from '
                    '${loan.counterparty} on $paidOn before confirming. '
                    'Confirming is final and updates both ledgers.'
              : 'Check your bank or UPI app for $amount paid to '
                    '${loan.counterparty} on $paidOn before confirming. '
                    'Confirming is final and updates both ledgers.'
        : repayment.recordedByYou
        ? '${loan.counterparty} must confirm this. Only the person who did '
              'not record it can act.'
        : 'This repayment has already been answered and is read-only.';
    return Scaffold(
      body: SettloScrollScaffold(
        title: 'Confirm repayment',
        largeTitle: 'Confirm repayment',
        children: [
          _header(context),

          SAvatar(loan.counterparty, size: 72),
          const SizedBox(height: SettloSpacing.x2),
          Text(
            summary,
            style: SettloTypography.headline(color: c.textSecondary),
          ),
          const SizedBox(height: 4),
          Semantics(
            label: spokenInr(repayment.amount),
            excludeSemantics: true,
            child: MoneyText(repayment.amount, size: 52),
          ),
          const SizedBox(height: SettloSpacing.x1),
          Text(
            'on $paidOn · $method$referenceText',
            textAlign: TextAlign.center,
            style: SettloTypography.subheadline(color: c.textSecondary),
          ),
          const SizedBox(height: 24),
          SCard(
            padding: const EdgeInsets.all(SettloSpacing.screenMargin),
            child: Column(
              children: [
                _Row(
                  'Loan',
                  MediaQuery.textScalerOf(context).scale(1) >= 1.3
                      ? '${loan.counterparty}\n${formatInr(loan.principal)}'
                      : '${loan.counterparty} · ${formatInr(loan.principal)}',
                  spoken:
                      '${loan.counterparty}, '
                      '${spokenInr(loan.principal)}',
                ),
                _Row('Instalment', switch ((
                  loan.installmentsAfter(repayment),
                  loan.installmentsTotal,
                )) {
                  (final paid?, final total?) => '$paid of $total',
                  _ => 'Flexible',
                }),
                _Row(
                  'Outstanding after',
                  formatInr(after),
                  spoken: spokenInr(after),
                ),
                _Row('Recorded by', '$recordedBy · $paidOn', last: true),
              ],
            ),
          ),
          const SizedBox(height: SettloSpacing.x2),
          SCard(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                LoanGlyph(
                  LoanGlyph.shieldCheck,
                  size: 20,
                  color: c.textSecondary,
                ),
                const SizedBox(width: SettloSpacing.x2),
                Expanded(
                  child: Text(
                    guidance,
                    style: SettloTypography.subheadline(color: c.textSecondary)
                        .copyWith(height: 1.5),
                  ),
                ),
              ],
            ),
          ),
          if (overpayment) ...[
            const SizedBox(height: SettloSpacing.x2),
            Text(
              'This is more than is left on the loan. Confirming '
              'will be refused.',
              textAlign: TextAlign.center,
              style: SettloTypography.subheadline(color: c.textPrimary),
            ),
          ],
          if (decision.error case final error?) ...[
            const SizedBox(height: SettloSpacing.x2),
            Text(
              error,
              textAlign: TextAlign.center,
              style: SettloTypography.subheadline(color: c.error),
            ),
          ],

          if (canAct) ...[
            const SizedBox(height: SettloSpacing.x2),
            SizedBox(
              width: double.infinity,
              child: SPrimaryButton(
                label: decision.busy
                    ? 'Confirming…'
                    : loan.youLent
                    ? 'Confirm $amount received'
                    : 'Confirm $amount paid',
                icon: LoanGlyph(
                  LoanGlyph.check,
                  color: c.onAction,
                  size: 18,
                  stroke: 1.9,
                ),
                onPressed: decision.busy || overpayment
                    ? null
                    : () async {
                        if (!await decision.confirm() ||
                            !context.mounted ||
                            // Mounted is not enough: the user may have gone
                            // Back (exit transition) or pushed past us.
                            ModalRoute.of(context)?.isCurrent != true) {
                          return;
                        }
                        showSettloNotice(
                          context,
                          'Confirmed. ${formatInr(after)} left',
                        );
                        if (context.canPop()) {
                          context.pop();
                        } else {
                          context.go(SettloRoutes.loan(loan.id));
                        }
                      },
              ),
            ),
            const SizedBox(height: SettloSpacing.x2),
            SizedBox(
              width: double.infinity,
              child: SSecondaryButton(
                label: loan.youLent ? "Didn't receive this" : "Didn't pay this",
                onPressed: decision.busy
                    ? null
                    : () => showSettloSheet<void>(
                        context: context,
                        builder: (context) => DisputeSheet(
                          repayment: repayment,
                          counterparty: loan.counterparty,
                          youLent: loan.youLent,
                          decision: decision,
                          onClose: () => Navigator.of(context).pop(),
                        ),
                      ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _Row extends StatelessWidget {
  const new(this.label, this.value, {this.spoken, this.last = false});

  final String label;
  final String value;
  final String? spoken;
  final bool last;

  @override
  Widget build(BuildContext context) {
    final c = SettloColors.of(context);
    return Semantics(
      label: '$label, ${spoken ?? value}',
      excludeSemantics: true,
      child: Container(
        constraints: const BoxConstraints(minHeight: 44),
        padding: const EdgeInsets.symmetric(vertical: SettloSpacing.x1),
        child: SResponsiveRow(
          children: [
            Text(label, style: SettloTypography.body(color: c.textSecondary)),
            const SizedBox(width: SettloSpacing.x2),
            Expanded(
              child: Text(
                value,
                textAlign: TextAlign.end,
                style: SettloTypography.body(
                  weight: label == 'Outstanding after'
                      ? FontWeight.w500
                      : FontWeight.w400,
                  color: c.textPrimary,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
