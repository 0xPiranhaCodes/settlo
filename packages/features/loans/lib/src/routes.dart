import 'package:go_router/go_router.dart';
import 'package:settlo_core/settlo_core.dart';
import 'package:settlo_loans/src/loan_detail.dart';
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

/// New loan and repayment confirmation, full screen over the tabs. They
/// are matched before the tab's `:loanId`.
final List<RouteBase> loansRoutes = [
  GoRoute(path: SettloRoutes.newLoan, builder: (_, _) => const NewLoanScreen()),
  GoRoute(
    path: SettloRoutes.confirmRepaymentPattern,
    builder: (_, state) => ConfirmRepaymentScreen(
      repaymentId: state.pathParameters['repaymentId']!,
    ),
  ),
];
