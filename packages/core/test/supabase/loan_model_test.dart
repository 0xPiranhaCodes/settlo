import 'package:flutter_test/flutter_test.dart';
import 'package:settlo_core/settlo_core.dart';

LoanRepayment _repayment(
  RepaymentStatus status, {
  Paise amount = const Paise.rupees(25000),
}) => LoanRepayment(
  id: status.name,
  amount: amount,
  paidOn: DateTime(2026, 10, 5),
  status: status,
  recordedByYou: false,
);

Loan _loan({
  Paise principal = const Paise.rupees(100000),
  Paise repaid = const Paise.rupees(50000),
  List<LoanRepayment> repayments = const [],
}) => Loan(
  id: 'loan',
  counterparty: 'Arjun',
  youLent: true,
  principal: principal,
  repaid: repaid,
  startOn: DateTime(2026),
  repayments: repayments,
);

void main() {
  group('outstanding after repayment', () {
    test('pending repayment is added to confirmed repayments', () {
      final repayment = _repayment(RepaymentStatus.pending);

      expect(
        _loan(repayments: [repayment]).outstandingAfter(repayment),
        const Paise.rupees(25000),
      );
    });

    test('confirmed repayment is already included', () {
      final repayment = _repayment(RepaymentStatus.confirmed);

      expect(
        _loan(repayments: [repayment]).outstandingAfter(repayment),
        const Paise.rupees(50000),
      );
    });

    test('disputed repayment never counts', () {
      final repayment = _repayment(RepaymentStatus.disputed);

      expect(
        _loan(repayments: [repayment]).outstandingAfter(repayment),
        const Paise.rupees(50000),
      );
    });

    test('last confirmed repayment leaves zero without subtracting twice', () {
      final repayment = _repayment(RepaymentStatus.confirmed);

      expect(
        _loan(
          principal: const Paise.rupees(25000),
          repaid: const Paise.rupees(25000),
          repayments: [repayment],
        ).outstandingAfter(repayment),
        Paise.zero,
      );
    });

    test('an earlier dispute does not reduce outstanding', () {
      final earlierDispute = _repayment(
        RepaymentStatus.disputed,
        amount: const Paise.rupees(40000),
      );
      final pending = _repayment(RepaymentStatus.pending);

      expect(
        _loan(repayments: [pending, earlierDispute]).outstandingAfter(pending),
        const Paise.rupees(25000),
      );
    });

    test('an overpayment never produces negative money', () {
      final repayment = _repayment(
        RepaymentStatus.pending,
        amount: const Paise.rupees(60000),
      );

      expect(
        _loan(repayments: [repayment]).outstandingAfter(repayment),
        Paise.zero,
      );
    });
  });
}
