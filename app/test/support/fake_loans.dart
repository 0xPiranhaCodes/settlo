import 'dart:async';

import 'package:settlo_core/settlo_core.dart';

/// The Loan artboard: you lent Arjun ₹10 lakh at ₹25,000 a month from
/// March; 13 instalments confirmed (32% repaid), and the 5 Oct one
/// recorded by Arjun waits for you.
Loan arjunLoan({List<LoanRepayment>? repayments, Paise? repaid}) => Loan(
  id: 'l1',
  counterparty: 'Arjun',
  youLent: true,
  principal: const Paise.rupees(1000000),
  repaid: repaid ?? const Paise.rupees(325000),
  startOn: DateTime(2026, 3, 5),
  installment: const Paise.rupees(25000),
  dueDay: 5,
  installmentsPaid: 13,
  installmentsTotal: 40,
  nextDueOn: DateTime(2026, 12, 5),
  endsOn: DateTime(2029, 7, 5),
  onTrack: true,
  repayments:
      repayments ??
      [
        LoanRepayment(
          id: 'r4',
          amount: const Paise.rupees(25000),
          paidOn: DateTime(2026, 11, 5),
          method: RepaymentMethod.upi,
          status: RepaymentStatus.confirmed,
          recordedByYou: false,
        ),
        LoanRepayment(
          id: 'r3',
          amount: const Paise.rupees(25000),
          paidOn: DateTime(2026, 10, 5),
          method: RepaymentMethod.upi,
          reference: '4321 8812 0099',
          status: RepaymentStatus.pending,
          recordedByYou: false,
        ),
        LoanRepayment(
          id: 'r2',
          amount: const Paise.rupees(25000),
          paidOn: DateTime(2026, 9, 5),
          method: RepaymentMethod.cash,
          status: RepaymentStatus.confirmed,
          recordedByYou: false,
        ),
        LoanRepayment(
          id: 'r1',
          amount: const Paise.rupees(25000),
          paidOn: DateTime(2026, 8, 5),
          method: RepaymentMethod.bank,
          status: RepaymentStatus.confirmed,
          recordedByYou: false,
        ),
      ],
);

/// The Loans tab: Arjun's loan, a flexible one you borrowed from Meera,
/// and one with Dev that is fully repaid.
LoansData loansList() => LoansData(
  today: DateTime(2026, 11, 9),
  yourName: 'Sana',
  loans: [
    arjunLoan(),
    Loan(
      id: 'l2',
      counterparty: 'Meera',
      youLent: false,
      principal: const Paise.rupees(40000),
      repaid: const Paise.rupees(15000),
      startOn: DateTime(2026, 9),
    ),
    Loan(
      id: 'l3',
      counterparty: 'Dev',
      youLent: false,
      principal: const Paise.rupees(5000),
      repaid: const Paise.rupees(5000),
      startOn: DateTime(2026),
      closed: true,
    ),
  ],
);

/// Loans in memory, moving as the server would: a recorded repayment is
/// pending and yours, a confirmed one counts, a disputed one never does.
/// Set [error] to make the next write throw it.
class FakeLoansRepository implements LoansRepository {
  /// Starts from [data].
  new(this.data);

  /// What [load] returns.
  LoansData data;

  /// Thrown by the next write, then cleared.
  Exception? error;

  /// Every write, as `rpc key`.
  final calls = <String>[];

  /// While set, writes wait for it, as a slow network would.
  Completer<void>? hold;

  /// Whether the next [load] fails.
  bool failLoad = false;

  @override
  Future<LoansData> load() async {
    if (failLoad) throw Exception('offline');
    return data;
  }

  Future<void> _throw() async {
    await hold?.future;
    final e = error;
    error = null;
    if (e != null) throw e;
  }

  void _update(String loanId, Loan Function(Loan) change) => data = LoansData(
    today: data.today,
    yourName: data.yourName,
    loans: [
      for (final l in data.loans)
        if (l.id == loanId) change(l) else l,
    ],
  );

  Loan _copy(Loan l, {Paise? repaid, List<LoanRepayment>? repayments}) => Loan(
    id: l.id,
    counterparty: l.counterparty,
    youLent: l.youLent,
    principal: l.principal,
    repaid: repaid ?? l.repaid,
    startOn: l.startOn,
    installment: l.installment,
    dueDay: l.dueDay,
    installmentsPaid: l.installmentsPaid,
    installmentsTotal: l.installmentsTotal,
    nextDueOn: l.nextDueOn,
    endsOn: l.endsOn,
    onTrack: l.onTrack,
    closed: l.closed,
    repayments: repayments ?? l.repayments,
  );

  /// What [createLoan] was last sent.
  NewLoan? created;

  @override
  Future<String> createLoan(
    NewLoan loan, {
    required String idempotencyKey,
  }) async {
    calls.add('create_loan $idempotencyKey');
    await _throw();
    created = loan;
    final i = loan.installment;
    data = LoansData(
      today: data.today,
      yourName: data.yourName,
      loans: [
        ...data.loans,
        // The other side has not joined: the name you gave, else the number.
        Loan(
          id: idempotencyKey,
          counterparty: loan.counterpartyName ?? loan.counterpartyPhone,
          youLent: loan.youLent,
          principal: loan.principal,
          repaid: Paise.zero,
          startOn: loan.startOn,
          installment: i,
          dueDay: loan.dueDay,
          installmentsPaid: i == null ? null : 0,
          installmentsTotal: i == null
              ? null
              : (loan.principal.value + i.value - 1) ~/ i.value,
        ),
      ],
    );
    return idempotencyKey;
  }

  @override
  Future<String> recordRepayment(
    NewRepayment repayment, {
    required String idempotencyKey,
  }) async {
    calls.add('record_repayment $idempotencyKey');
    await _throw();
    _update(
      repayment.loanId,
      (l) => _copy(
        l,
        repayments: [
          LoanRepayment(
            id: idempotencyKey,
            amount: repayment.amount,
            paidOn: repayment.paidOn ?? data.today,
            method: repayment.method,
            reference: repayment.reference,
            status: RepaymentStatus.pending,
            recordedByYou: true,
          ),
          ...l.repayments,
        ],
      ),
    );
    return idempotencyKey;
  }

  Future<void> _answer(
    String repaymentId,
    RepaymentStatus status, [
    String? reason,
  ]) async {
    final loan = data.loans.firstWhere(
      (l) => l.repayments.any((r) => r.id == repaymentId),
    );
    final r = loan.repayments.firstWhere((r) => r.id == repaymentId);
    _update(
      loan.id,
      (l) => _copy(
        l,
        repaid: status == RepaymentStatus.confirmed
            ? l.repaid + r.amount
            : null,
        repayments: [
          for (final x in l.repayments)
            if (x.id == repaymentId)
              LoanRepayment(
                id: x.id,
                amount: x.amount,
                paidOn: x.paidOn,
                method: x.method,
                reference: x.reference,
                status: status,
                recordedByYou: x.recordedByYou,
                disputeReason: reason,
              )
            else
              x,
        ],
      ),
    );
  }

  @override
  Future<void> confirmRepayment(
    String repaymentId, {
    required String idempotencyKey,
  }) async {
    calls.add('confirm_repayment $idempotencyKey');
    await _throw();
    await _answer(repaymentId, RepaymentStatus.confirmed);
  }

  @override
  Future<void> disputeRepayment(
    String repaymentId, {
    required String reason,
    required String idempotencyKey,
  }) async {
    calls.add('dispute_repayment $idempotencyKey $reason');
    await _throw();
    await _answer(repaymentId, RepaymentStatus.disputed, reason);
  }
}
