import 'package:settlo_core/settlo_core.dart';

/// Flat 4B: Sana (you), Priya in Devanagari, Zoë, and someone known only
/// by their number; Ravi left.
SpaceSummary flat() => const SpaceSummary(
  id: 's1',
  name: 'Flat 4B',
  kind: SpaceKind.flat,
  members: [
    SpaceMember(
      id: 'm1',
      name: 'Sana',
      phone: '+919800000001',
      isYou: true,
      balance: Paise(-3333),
    ),
    SpaceMember(
      id: 'm2',
      name: 'प्रिया',
      phone: '+919800000002',
      balance: Paise(6668),
    ),
    SpaceMember(
      id: 'm3',
      name: 'Zoë',
      phone: '+919800000003',
      balance: Paise(-3335),
    ),
    SpaceMember(id: 'm4', name: '+919800000004', phone: '+919800000004'),
  ],
  departed: [SpaceMember(id: 'm5', name: 'Ravi', phone: '+919800000005')],
);

List<ExpenseSplit> _equal(Paise amount, List<String> ids, String payer) => [
  for (final e in splitEqual(amount, ids, payer: payer).entries)
    (memberId: e.key, amount: e.value, percentBp: null, shares: null),
];

/// Newest first, as the repository returns them.
SpaceLedger flatLedger() => SpaceLedger(
  today: DateTime(2026, 11, 10),
  expenses: [
    SpaceExpense(
      id: 'e4',
      description: 'Settle up',
      amount: const Paise(3333),
      spentOn: DateTime(2026, 11, 9),
      isSettlement: true,
      settlementStatus: SettlementStatus.pending,
      payers: const [(memberId: 'm1', amount: Paise(3333))],
      splits: const [
        (memberId: 'm2', amount: Paise(3333), percentBp: null, shares: null),
      ],
    ),
    SpaceExpense(
      id: 'e3',
      description: '=HYPERLINK("x")',
      amount: const Paise(50000),
      spentOn: DateTime(2026, 11, 8),
      isSettlement: true,
      settlementStatus: SettlementStatus.confirmed,
      payers: const [(memberId: 'm3', amount: Paise(50000))],
      splits: const [
        (memberId: 'm2', amount: Paise(50000), percentBp: null, shares: null),
      ],
    ),
    SpaceExpense(
      id: 'e2',
      description: 'Dinner, "Truffles" & dessert',
      category: 'food',
      amount: const Paise(10001),
      spentOn: DateTime(2026, 11, 2),
      payers: const [(memberId: 'm2', amount: Paise(10001))],
      splits: _equal(const Paise(10001), ['m1', 'm2', 'm3'], 'm2'),
    ),
    SpaceExpense(
      id: 'e1',
      description: 'Rent',
      amount: const Paise.rupees(42000),
      spentOn: DateTime(2026, 11),
      payers: const [(memberId: 'm5', amount: Paise.rupees(42000))],
      splits: _equal(const Paise.rupees(42000), ['m1', 'm4', 'm5'], 'm5'),
    ),
  ],
);

/// Sana lent Arjun ₹10 lakh at ₹25,000 a month: three confirmed, one
/// awaiting her and one she disputed.
Loan arjunLoan() => Loan(
  id: 'l1',
  counterparty: 'Arjun',
  youLent: true,
  principal: const Paise.rupees(1000000),
  repaid: const Paise.rupees(75000),
  startOn: DateTime(2026, 8, 5),
  installment: const Paise.rupees(25000),
  dueDay: 5,
  installmentsPaid: 3,
  installmentsTotal: 40,
  nextDueOn: DateTime(2026, 12, 5),
  endsOn: DateTime(2029, 11, 5),
  onTrack: true,
  repayments: [
    LoanRepayment(
      id: 'r5',
      amount: const Paise(2500050),
      paidOn: DateTime(2026, 11, 6),
      method: RepaymentMethod.upi,
      reference: '4321 8812 0099',
      status: RepaymentStatus.pending,
      recordedByYou: false,
    ),
    LoanRepayment(
      id: 'r4',
      amount: const Paise.rupees(25000),
      paidOn: DateTime(2026, 11, 5),
      method: RepaymentMethod.cash,
      status: RepaymentStatus.disputed,
      recordedByYou: false,
      disputeReason: 'Not received',
    ),
    for (final (id, month) in [('r3', 10), ('r2', 9), ('r1', 8)])
      LoanRepayment(
        id: id,
        amount: const Paise.rupees(25000),
        paidOn: DateTime(2026, month, 5),
        method: RepaymentMethod.bank,
        status: RepaymentStatus.confirmed,
        recordedByYou: false,
      ),
  ],
);
