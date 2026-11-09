import 'package:flutter/widgets.dart';
import 'package:settlo_core/settlo_core.dart';

/// Placeholder for the Loan artboard.
class LoanScreen extends StatelessWidget {
  /// The Loan screen.
  const new({super.key});

  @override
  Widget build(BuildContext context) =>
      const SPlaceholderScreen(title: 'Loans', artboard: 'Loan');
}

/// Placeholder for the NewLoan artboard.
class NewLoanScreen extends StatelessWidget {
  /// The NewLoan screen.
  const new({super.key});

  @override
  Widget build(BuildContext context) =>
      const SPlaceholderScreen(title: 'New loan', artboard: 'NewLoan');
}

/// Placeholder for the ConfirmRepayment artboard.
class ConfirmRepaymentScreen extends StatelessWidget {
  /// The ConfirmRepayment screen for [repaymentId].
  const new({required this.repaymentId, super.key});

  /// The repayment to confirm.
  final String repaymentId;

  @override
  Widget build(BuildContext context) => const SPlaceholderScreen(
    title: 'Confirm repayment',
    artboard: 'ConfirmRepayment',
  );
}
