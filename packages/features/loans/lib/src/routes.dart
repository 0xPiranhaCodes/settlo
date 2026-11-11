import 'package:go_router/go_router.dart';
import 'package:settlo_core/settlo_core.dart';
import 'package:settlo_loans/src/confirm_repayment.dart';
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
      // Explicit pages: go_router's default here has no iOS swipe back.
      pageBuilder: (_, state) => SettloPage<void>(
        key: state.pageKey,
        child: LoanDetailScreen(loanId: state.pathParameters['loanId']!),
      ),
    ),
  ],
);

/// New loan, a sheet over whatever opened it (Loans or Home), and
/// repayment confirmation, full screen over the tabs. They are matched
/// before the tab's `:loanId`.
final List<RouteBase> loansRoutes = [
  GoRoute(
    path: SettloRoutes.newLoan,
    pageBuilder: (context, state) =>
        SettloSheetPage<void>(key: state.pageKey, child: const NewLoanSheet()),
  ),
  GoRoute(
    path: SettloRoutes.confirmRepaymentPattern,
    pageBuilder: (_, state) => SettloPage<void>(
      key: state.pageKey,
      child: ConfirmRepaymentScreen(
        repaymentId: state.pathParameters['repaymentId']!,
      ),
    ),
  ),
];
