import 'package:settlo_core/settlo_core.dart';

import 'fake_space_ledger.dart';

/// The Activity artboard on 9 Nov: Priya's and your spending today, then
/// Arjun's confirmed repayment, Kabir settling with you, and Rahul's edit
/// of the wifi bill this week.
final activityFeed = [
  ActivityEntry(
    id: 6,
    at: DateTime(2026, 11, 9, 9, 30),
    kind: ActivityKind.expense,
    action: ActivityAction.created,
    byYou: false,
    actor: 'Priya',
    spaceId: 's1',
    spaceName: 'Flat 402',
    description: 'Electricity',
    amount: const Paise.rupees(2340),
  ),
  ActivityEntry(
    id: 5,
    at: DateTime(2026, 11, 9, 8),
    kind: ActivityKind.expense,
    action: ActivityAction.created,
    byYou: true,
    actor: 'Sana',
    spaceId: 's1',
    spaceName: 'Flat 402',
    description: 'Groceries',
    amount: const Paise.rupees(1800),
  ),
  ActivityEntry(
    id: 4,
    at: DateTime(2026, 11, 5, 10),
    kind: ActivityKind.repayment,
    action: ActivityAction.confirmed,
    byYou: true,
    loanId: 'l1',
    counterparty: 'Arjun',
    amount: const Paise.rupees(25000),
    status: ActivityStatus.confirmed,
    toYou: true,
  ),
  ActivityEntry(
    id: 3,
    at: DateTime(2026, 11, 4, 19),
    kind: ActivityKind.settlement,
    action: ActivityAction.created,
    byYou: false,
    actor: 'Kabir',
    spaceId: 's2',
    spaceName: 'Goa trip',
    description: 'Settle up',
    amount: const Paise.rupees(1200),
    status: ActivityStatus.confirmed,
    toYou: true,
  ),
  ActivityEntry(
    id: 2,
    at: DateTime(2026, 11, 3, 21),
    kind: ActivityKind.expense,
    action: ActivityAction.edited,
    byYou: false,
    actor: 'Rahul',
    spaceId: 's1',
    spaceName: 'Flat 402',
    description: 'Wifi · Airtel',
    amount: const Paise.rupees(1199),
    beforeDescription: 'Wifi · Airtel',
    beforeAmount: const Paise.rupees(1099),
  ),
];

/// Arjun's 5 Oct repayment (`loansList`'s `r3`) waits for you.
final arjunRepaymentAnswer = PendingAnswer(
  id: 'r3',
  isRepayment: true,
  counterparty: 'Arjun',
  amount: const Paise.rupees(25000),
  paidOn: DateTime(2026, 10, 5),
  recordedAt: DateTime(2026, 10, 5, 10),
  loanId: 'l1',
);

/// Rahul's ₹300 settle-up in Flat 402 (`flatLedgerWithSettleUp`'s `e11`)
/// waits for you.
final rahulSettleUpAnswer = PendingAnswer(
  id: 'e11',
  isRepayment: false,
  counterparty: 'Rahul',
  amount: const Paise.rupees(300),
  paidOn: DateTime(2026, 11, 9),
  recordedAt: DateTime(2026, 11, 9, 11),
  spaceId: 's1',
  spaceName: 'Flat 402',
);

/// An [ActivityRepository] over [entries] and [pending]. With [ledger], a
/// settle-up waits only while the ledger still has it pending, as the
/// `needs_you` view would.
class FakeActivityRepository implements ActivityRepository {
  /// Serves [entries] (newest first) and [pending].
  new({List<ActivityEntry>? entries, List<PendingAnswer>? pending, this.ledger})
    : entries = entries ?? activityFeed,
      pending = pending ?? [arjunRepaymentAnswer];

  /// The feed, newest first.
  final List<ActivityEntry> entries;

  /// What waits for you.
  final List<PendingAnswer> pending;

  /// The space ledgers settle-ups are answered in.
  final FakeSpaceLedgerRepository? ledger;

  /// Every read, as `feed <limit> <before>` or `needsYou`.
  final calls = <String>[];

  @override
  Future<List<ActivityEntry>> feed({required int limit, int? before}) async {
    calls.add('feed $limit $before');
    return entries
        .where((e) => before == null || e.id < before)
        .take(limit)
        .toList();
  }

  @override
  Future<List<PendingAnswer>> needsYou() async {
    calls.add('needsYou');
    final ledgers = ledger?.ledgers;
    return [
      for (final a in pending)
        if (a.isRepayment ||
            ledgers == null ||
            ledgers[a.spaceId]!.expenses.any(
              (e) =>
                  e.id == a.id &&
                  e.settlementStatus == SettlementStatus.pending,
            ))
          a,
    ];
  }
}
