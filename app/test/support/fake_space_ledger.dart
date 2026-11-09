import 'package:settlo_core/settlo_core.dart';

SpaceExpense _expense(
  String id,
  String description,
  int rupees,
  int day, {
  required String paidBy,
  List<String> between = const ['m1', 'm2', 'm3'],
  String? category,
  bool byYou = false,
  bool settlement = false,
  String splitType = 'equal',
}) {
  final amount = Paise.rupees(rupees);
  final each = amount.value ~/ between.length;
  return SpaceExpense(
    id: id,
    description: description,
    category: category,
    amount: amount,
    spentOn: DateTime(2026, 11, day),
    splitType: splitType,
    isSettlement: settlement,
    createdByYou: byYou,
    payers: [(memberId: paidBy, amount: amount)],
    splits: [
      for (final (i, m) in between.indexed)
        (
          memberId: m,
          amount: Paise(
            each + (i == 0 ? amount.value - each * between.length : 0),
          ),
          percentBp: null,
          shares: splitType == 'shares' ? 1 : null,
        ),
    ],
  );
}

/// The SpaceExpenses and Space artboards for Flat 402 (`spacesList`'s
/// `s1`) on 9 November: you paid ₹9,000, Rahul ₹5,400 and Priya ₹4,050
/// against ₹6,150 each.
final flatLedger = SpaceLedger(
  today: DateTime(2026, 11, 9),
  expenses: [
    _expense(
      'e1',
      'Groceries · BigBasket',
      1800,
      9,
      paidBy: 'm1',
      category: 'groceries',
      byYou: true,
    ),
    _expense('e2', 'Electricity', 2340, 9, paidBy: 'm3', category: 'utilities'),
    _expense(
      'e3',
      'Wifi · Airtel',
      1199,
      8,
      paidBy: 'm2',
      category: 'utilities',
      splitType: 'shares',
    ),
    _expense(
      'e4',
      'Maid · November',
      3000,
      8,
      paidBy: 'm1',
      category: 'household',
      byYou: true,
    ),
    _expense(
      'e5',
      'Dinner · Truffles',
      3100,
      6,
      paidBy: 'm2',
      category: 'food',
    ),
    _expense(
      'e6',
      'Cook · November',
      4200,
      5,
      paidBy: 'm1',
      category: 'household',
      byYou: true,
    ),
    _expense('e7', 'Cleaning supplies', 810, 4, paidBy: 'm3'),
    _expense(
      'e8',
      'Gas cylinder',
      1101,
      2,
      paidBy: 'm2',
      category: 'utilities',
    ),
    _expense('e9', 'Milk · Nov', 900, 1, paidBy: 'm3', category: 'groceries'),
  ],
  fairness: const {
    'm1': (paid: Paise.rupees(9000), fairShare: Paise.rupees(6150)),
    'm2': (paid: Paise.rupees(5400), fairShare: Paise.rupees(6150)),
    'm3': (paid: Paise.rupees(4050), fairShare: Paise.rupees(6150)),
  },
  categories: const [
    (category: 'household', total: Paise.rupees(7200), count: 2),
    (category: 'utilities', total: Paise.rupees(4640), count: 3),
    (category: 'food', total: Paise.rupees(3100), count: 1),
    (category: 'groceries', total: Paise.rupees(2700), count: 2),
    (category: null, total: Paise.rupees(810), count: 1),
  ],
);

/// [flatLedger] with Rahul paying you back ₹500 today: a settle-up, so
/// it is listed but is not spending.
final flatLedgerWithSettleUp = SpaceLedger(
  today: flatLedger.today,
  fairness: flatLedger.fairness,
  categories: flatLedger.categories,
  expenses: [
    _expense(
      'e10',
      'Rahul paid you back',
      500,
      9,
      paidBy: 'm2',
      between: ['m1'],
      settlement: true,
      splitType: 'exact',
    ),
    ...flatLedger.expenses,
  ],
);

/// Goa trip (`spacesList`'s `s2`), where you are not an owner: you may
/// change only what you recorded.
final tripLedger = SpaceLedger(
  today: DateTime(2026, 11, 9),
  expenses: [
    _expense(
      't1',
      'Scooters',
      1200,
      9,
      paidBy: 'm4',
      between: ['m4', 'm5'],
      byYou: true,
    ),
    _expense('t2', 'Shack lunch', 2450, 9, paidBy: 'm8', between: ['m4', 'm8']),
  ],
);

/// A [SpaceLedgerRepository] over [ledgers] by space id that applies
/// edits and deletes as the server would: a replayed key changes nothing.
class FakeSpaceLedgerRepository implements SpaceLedgerRepository {
  /// Serves [ledgers].
  new([Map<String, SpaceLedger>? ledgers])
    : ledgers = Map.of(ledgers ?? {'s1': flatLedger, 's2': tripLedger});

  /// What [load] returns next, by space id.
  final Map<String, SpaceLedger> ledgers;

  /// When set, the next call throws it.
  Exception? failure;

  /// Every write, as `update <key> <id> <description> <paise>` or
  /// `delete <key> <id>`.
  final calls = <String>[];

  final _seen = <String>{};

  void _throwOnce() {
    if (failure case final e?) {
      failure = null;
      throw e;
    }
  }

  @override
  Future<SpaceLedger> load(String spaceId) async {
    _throwOnce();
    return ledgers[spaceId] ?? SpaceLedger(today: DateTime(2026, 11, 9));
  }

  void _replace(String id, SpaceExpense? Function(SpaceExpense) change) {
    for (final MapEntry(:key, :value) in ledgers.entries.toList()) {
      ledgers[key] = SpaceLedger(
        today: value.today,
        fairness: value.fairness,
        categories: value.categories,
        expenses: [
          for (final e in value.expenses)
            if (e.id != id) e else ?change(e),
        ],
      );
    }
  }

  @override
  Future<void> updateExpense(
    ExpenseUpdate update, {
    required String idempotencyKey,
  }) async {
    calls.add(
      'update $idempotencyKey ${update.id} ${update.description} '
      '${update.amount.value}',
    );
    _throwOnce();
    if (!_seen.add(idempotencyKey)) return;
    _replace(
      update.id,
      (e) => SpaceExpense(
        id: e.id,
        description: update.description,
        category: update.category,
        amount: update.amount,
        spentOn: update.spentOn,
        isSettlement: update.isSettlement,
        splitType: update.splitType,
        createdByYou: e.createdByYou,
        payers: update.payers,
        splits: update.splits,
      ),
    );
  }

  @override
  Future<void> deleteExpense(
    String expenseId, {
    required String idempotencyKey,
  }) async {
    calls.add('delete $idempotencyKey $expenseId');
    _throwOnce();
    if (!_seen.add(idempotencyKey)) return;
    _replace(expenseId, (_) => null);
  }
}
