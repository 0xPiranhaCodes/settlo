import 'package:flutter/widgets.dart';
import 'package:go_router/go_router.dart';
import 'package:settlo_core/settlo_core.dart';
import 'package:settlo_loans/src/loan_detail.dart';
import 'package:settlo_loans/src/new_loan_sheet.dart';
import 'package:settlo_loans/src/screens.dart';

/// The Loans tab, with a loan's detail under it.
final GoRoute loansTabRoute = GoRoute(
  path: SettloRoutes.loans,
  builder: (_, _) => const LoanScreen(),
  routes: [
    GoRoute(
      path: ':loanId',
      builder: (_, state) =>
          LoanDetailScreen(loanId: state.pathParameters['loanId']!),
    ),
  ],
);

/// New loan, a sheet over whatever opened it (Loans or Home), and
/// repayment confirmation, full screen over the tabs. They are matched
/// before the tab's `:loanId`.
final List<RouteBase> loansRoutes = [
  GoRoute(
    path: SettloRoutes.newLoan,
    pageBuilder: (context, state) => CustomTransitionPage<void>(
      key: state.pageKey,
      opaque: false,
      barrierDismissible: true,
      barrierColor: SettloColors.of(context).background.withValues(alpha: 0.6),
      transitionsBuilder: (_, animation, _, child) => SlideTransition(
        position: Tween(begin: const Offset(0, 1), end: Offset.zero).animate(
          CurvedAnimation(parent: animation, curve: Curves.easeOutCubic),
        ),
        child: child,
      ),
      child: const NewLoanSheet(),
    ),
  ),
  GoRoute(
    path: SettloRoutes.confirmRepaymentPattern,
    builder: (_, state) => ConfirmRepaymentScreen(
      repaymentId: state.pathParameters['repaymentId']!,
    ),
  ),
];
