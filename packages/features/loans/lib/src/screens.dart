import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:settlo_core/settlo_core.dart';
import 'package:settlo_loans/src/glyphs.dart';
import 'package:settlo_loans/src/loans_provider.dart';

/// The Loans tab: every loan you have accepted, open ones first, each
/// with what is outstanding from your side and its progress from
/// confirmed repayments. A loan with a repayment waiting for you says so.
class LoanScreen extends ConsumerWidget {
  /// The Loans tab.
  const new({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final loans = ref.watch(loansProvider);
    final c = SettloColors.of(context);
    final list = loans.value?.loans;
    return Scaffold(
      body: SettloTabScaffold(
        title: 'Loans',
        onRefresh: () => ref.refresh(loansProvider.future),
        children: [
          SettloNavigationHeader(
            title: 'Loans',
            trailing: SettloTabActions(
              onBell: () => context.go(SettloRoutes.activity),
              leading: GlassAction(
                label: 'New loan',
                symbol: 'plus',
                onPressed: () => context.push(SettloRoutes.newLoan),
                fallback: IconButton(
                  tooltip: 'New loan',
                  onPressed: () => context.push(SettloRoutes.newLoan),
                  style: IconButton.styleFrom(
                    fixedSize: const Size.square(SettloSpacing.minTouchTarget),
                    minimumSize: Size.zero,
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    backgroundColor: c.surface,
                    side: BorderSide(color: c.hairline),
                  ),
                  icon: LoanGlyph(LoanGlyph.plus, color: c.textPrimary),
                ),
              ),
            ),
          ),
          if (list == null)
            Text(
              loans.hasError
                  ? "We couldn't load your loans. Pull down to try again."
                  : '',
              style: SettloTypography.subheadline(color: c.textSecondary),
            )
          else if (list.isEmpty)
            SGroup(
              margin: EdgeInsets.zero,
              children: [
                Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Text(
                        'No loans yet',
                        style: SettloTypography.headline(color: c.textPrimary),
                      ),
                      const SizedBox(height: SettloSpacing.x1),
                      Text(
                        'Lent or borrowed a larger sum? Record it once and '
                        'both of you track every repayment.',
                        style: SettloTypography.body(color: c.textSecondary),
                      ),
                      const SizedBox(height: SettloSpacing.x3),
                      SPrimaryButton(
                        label: 'Record a loan',
                        onPressed: () => context.push(SettloRoutes.newLoan),
                      ),
                    ],
                  ),
                ),
              ],
            )
          else ...[
            if (list.any((l) => !l.closed))
              SGroup(
                margin: EdgeInsets.zero,
                children: [
                  for (final (i, l) in list.where((l) => !l.closed).indexed)
                    _LoanCard(
                      l,
                      separator: i < list.where((l) => !l.closed).length - 1,
                    ),
                ],
              ),
            if (list.any((l) => l.closed)) ...[
              const SizedBox(height: 8),
              const SSectionLabel('Repaid'),
              SGroup(
                margin: EdgeInsets.zero,
                children: [
                  for (final (i, l) in list.where((l) => l.closed).indexed)
                    _LoanCard(
                      l,
                      separator: i < list.where((l) => l.closed).length - 1,
                    ),
                ],
              ),
            ],
          ],
        ],
      ),
    );
  }
}

/// A loan in the list; opens its detail.
class _LoanCard extends StatelessWidget {
  const new(this.loan, {required this.separator});
  final bool separator;

  final Loan loan;

  /// What the row says under the name.
  String get _detail {
    final side = loan.youLent ? 'you lent' : 'you borrowed';
    if (loan.closed) return '$side · repaid';
    final (paid, total) = (loan.installmentsPaid, loan.installmentsTotal);
    if (paid == null || total == null) return '$side · flexible';
    return switch (loan.nextDueOn) {
      final next? => '$side · $paid of $total · next ${dayMonth(next)}',
      null => '$side · $paid of $total',
    };
  }

  @override
  Widget build(BuildContext context) {
    final waiting = loan.repayments.where((r) => r.awaitsYou).length;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SRow(
          title: '${loan.counterparty} · interest free',
          subtitle: _detail,
          leading: SAvatar(loan.counterparty, size: 36),
          scaleLeading: true,
          trailing: MoneyText(
            loan.outstanding,
            size: 17,
            tone: switch (loan) {
              Loan(closed: true) => MoneyTone.settled,
              Loan(youLent: true) => MoneyTone.owedToYou,
              _ => MoneyTone.youOwe,
            },
          ),
          separator: false,
          chevron: true,
          onTap: () => context.go(SettloRoutes.loan(loan.id)),
        ),
        if (waiting > 0)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
            child: Row(
              children: [
                Icon(
                  CupertinoIcons.clock,
                  size:
                      14 *
                      MediaQuery.textScalerOf(context).scale(1).clamp(1, 1.5),
                  color: SettloColors.of(context).pending,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    '$waiting repayment${waiting == 1 ? '' : 's'} to confirm',
                    style: SettloTypography.footnote(
                      color: SettloColors.of(context).pending,
                    ),
                  ),
                ),
              ],
            ),
          ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(2),
            child: LinearProgressIndicator(
              value: loan.progress,
              minHeight: 4,
              backgroundColor: SettloColors.of(context).surfaceRaised,
              color: SettloColors.of(context).brandAccent,
            ),
          ),
        ),
        if (separator)
          Divider(
            height: 0.5,
            thickness: 0.5,
            indent: 64,
            color: SettloColors.of(context).hairline,
          ),
      ],
    );
  }
}
