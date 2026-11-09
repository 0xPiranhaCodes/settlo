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
  Paise? installment,
  int? installmentsPaid,
  int? installmentsTotal,
  List<LoanRepayment> repayments = const [],
}) => Loan(
  id: 'loan',
  counterparty: 'Arjun',
  youLent: true,
  principal: principal,
  repaid: repaid,
  startOn: DateTime(2026),
  installment: installment,
  installmentsPaid: installmentsPaid,
  installmentsTotal: installmentsTotal,
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

  group('instalment after repayment', () {
    Loan scheduled(LoanRepayment repayment) => _loan(
      principal: const Paise.rupees(1000000),
      repaid: const Paise.rupees(325000),
      installment: const Paise.rupees(25000),
      installmentsPaid: 13,
      installmentsTotal: 40,
      repayments: [repayment],
    );

    test(
      'pending receipt projects complete instalments after confirmation',
      () {
        final repayment = _repayment(RepaymentStatus.pending);

        expect(scheduled(repayment).installmentsAfter(repayment), 14);
      },
    );

    test('pending projection floors partial amounts and caps at total', () {
      final partial = _repayment(
        RepaymentStatus.pending,
        amount: const Paise.rupees(24999),
      );
      final overSchedule = _repayment(
        RepaymentStatus.pending,
        amount: const Paise.rupees(700000),
      );

      expect(scheduled(partial).installmentsAfter(partial), 13);
      expect(scheduled(overSchedule).installmentsAfter(overSchedule), 40);
    });

    test('confirmed receipt keeps the current count', () {
      final repayment = _repayment(RepaymentStatus.confirmed);

      expect(scheduled(repayment).installmentsAfter(repayment), 13);
    });

    test('disputed receipt keeps the current count', () {
      final repayment = _repayment(RepaymentStatus.disputed);

      expect(scheduled(repayment).installmentsAfter(repayment), 13);
    });

    test('flexible loan has no instalment count', () {
      final repayment = _repayment(RepaymentStatus.pending);

      expect(_loan(repayments: [repayment]).installmentsAfter(repayment), null);
    });
  });
}
