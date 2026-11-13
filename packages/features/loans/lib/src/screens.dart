import 'dart:math' as math;

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
    final media = MediaQuery.of(context);
    final list = loans.value?.loans;
    return Scaffold(
      body: SettloScrollScaffold(
        title: 'Loans',
        stickyHeader: false,
        onRefresh: () => ref.refresh(loansProvider.future),
        padding: EdgeInsets.fromLTRB(
          SettloSpacing.screenMargin,
          math.max(media.padding.top, 44) + 16,
          SettloSpacing.screenMargin,
          media.padding.bottom + SettloSpacing.x2,
        ),
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
          const SizedBox(height: SettloSpacing.x3),
          if (list == null)
            Text(
              loans.hasError
                  ? "We couldn't load your loans. Pull down to try again."
                  : '',
              style: SettloTypography.subheadline(color: c.textSecondary),
            )
          else if (list.isEmpty)
            SCard(
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
            )
          else
            for (final (i, l) in list.indexed) ...[
              if (i > 0) const SizedBox(height: SettloSpacing.x3),
              _LoanCard(l),
            ],
        ],
      ),
    );
  }
}

/// A loan in the list; opens its detail.
class _LoanCard extends StatelessWidget {
  const new(this.loan);

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
    final c = SettloColors.of(context);
    final waiting = loan.repayments.where((r) => r.awaitsYou).length;
    return SPressable(
      onTap: () => context.go(SettloRoutes.loan(loan.id)),
      ringRadius: BorderRadius.circular(SettloRadius.card),
      child: SCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            SResponsiveRow(
              threshold: 1.3,
              children: [
                ExcludeSemantics(child: SAvatar(loan.counterparty)),
                const SizedBox(width: SettloSpacing.x2),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '${loan.counterparty} · interest free',
                        maxLines:
                            MediaQuery.textScalerOf(context).scale(1) >= 1.3
                            ? 2
                            : 1,
                        overflow: TextOverflow.ellipsis,
                        style: SettloTypography.headline(color: c.textPrimary),
                      ),
                      Text(
                        _detail,
                        maxLines:
                            MediaQuery.textScalerOf(context).scale(1) >= 1.3
                            ? 2
                            : 1,
                        overflow: TextOverflow.ellipsis,
                        style: SettloTypography.subheadline(
                          color: c.textSecondary,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: SettloSpacing.x2),
                MoneyText(
                  loan.outstanding,
                  tone: switch (loan) {
                    Loan(closed: true) => MoneyTone.settled,
                    Loan(youLent: true) => MoneyTone.owedToYou,
                    _ => MoneyTone.youOwe,
                  },
                ),
              ],
            ),
            const SizedBox(height: SettloSpacing.x2),
            ClipRRect(
              borderRadius: BorderRadius.circular(2),
              child: LinearProgressIndicator(
                value: loan.progress,
                minHeight: 4,
                backgroundColor: c.surfaceHighest,
                color: c.brandAccent,
              ),
            ),
            if (waiting > 0) ...[
              const SizedBox(height: SettloSpacing.x2),
              Row(
                children: [
                  Icon(Icons.schedule, size: 16, color: c.pending),
                  const SizedBox(width: 6),
                  Flexible(
                    child: Text(
                      waiting == 1
                          ? '1 repayment to confirm'
                          : '$waiting repayments to confirm',
                      style: SettloTypography.subheadline(color: c.pending),
                    ),
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }
}
