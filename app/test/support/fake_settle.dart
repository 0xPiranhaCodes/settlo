import 'package:settlo_core/settlo_core.dart';

import 'fake_expenses.dart';
import 'fake_spaces.dart';

/// The Settle and SettlePay artboards: in Flat 402 Priya owes you
/// ₹2,100; in Goa trip you owe Kabir ₹3,650. Both have UPI ids.
List<SpaceSummary> settleSpaces({
  String? yourUpiId = 'sana@okaxis',
  String? kabirUpiId = 'kabir@oksbi',
}) => [
  SpaceSummary(
    id: 's1',
    name: 'Flat 402',
    kind: SpaceKind.flat,
    hasExpenses: true,
    members: [
      SpaceMember(
        id: 'm1',
        name: 'Sana',
        phone: '+919876543210',
        isYou: true,
        balance: const Paise.rupees(2100),
        upiId: yourUpiId,
      ),
      const SpaceMember(
        id: 'm3',
        name: 'Priya',
        phone: '+919900000010',
        balance: Paise.rupees(-2100),
      ),
    ],
  ),
  SpaceSummary(
    id: 's2',
    name: 'Goa trip',
    kind: SpaceKind.trip,
    hasExpenses: true,
    members: [
      SpaceMember(
        id: 'm4',
        name: 'Sana',
        phone: '+919876543210',
        isYou: true,
        balance: const Paise.rupees(-3650),
        upiId: yourUpiId,
      ),
      SpaceMember(
        id: 'm5',
        name: 'Kabir',
        phone: '+919800002210',
        balance: const Paise.rupees(3650),
        upiId: kabirUpiId,
      ),
    ],
  ),
];

/// Goa trip where you owe ₹3,650: ₹1,650 to Kabir, still in the space,
/// and ₹2,000 to Arun, who has left.
List<SpaceSummary> settleSpacesWithDeparted() => [
  const SpaceSummary(
    id: 's2',
    name: 'Goa trip',
    kind: SpaceKind.trip,
    hasExpenses: true,
    members: [
      SpaceMember(
        id: 'm4',
        name: 'Sana',
        phone: '+919876543210',
        isYou: true,
        balance: Paise.rupees(-3650),
        upiId: 'sana@okaxis',
      ),
      SpaceMember(
        id: 'm5',
        name: 'Kabir',
        phone: '+919800002210',
        balance: Paise.rupees(1650),
        upiId: 'kabir@oksbi',
      ),
    ],
    departed: [
      SpaceMember(
        id: 'm6',
        name: 'Arun',
        phone: '+919100000002',
        balance: Paise.rupees(2000),
        upiId: 'arun@okicici',
      ),
    ],
  ),
];

/// Records expenses as [FakeExpensesRepository] does, and moves the
/// balances in [spaces] as the server would: payers up, splits down. A
/// settle-up you pay waits for the payee instead (#78): it joins
/// `pendingFromYou` until [answer], and a second one to the same payee
/// is refused as the server does.
class SettlingExpensesRepository extends FakeExpensesRepository {
  /// Settles into [spaces].
  new(this.spaces);

  /// The spaces whose balances a recorded expense changes.
  final FakeSpacesRepository spaces;

  @override
  Future<String> add(
    NewExpense expense, {
    required String idempotencyKey,
  }) async {
    final s = spaces.spaces.firstWhere((s) => s.id == expense.spaceId);
    final you = s.you;
    final payee = expense.splits.single.memberId;
    final pending = expense.isSettlement && expense.payers.containsKey(you.id);
    if (pending && s.pendingFromYou.any((p) => p.to.id == payee)) {
      calls.add((key: idempotencyKey, expense: expense));
      throw const SettlementPending();
    }
    final id = await super.add(expense, idempotencyKey: idempotencyKey);
    if (pending) {
      _replace(
        s,
        pending: [
          ...s.pendingFromYou,
          (
            from: you,
            to: s.members.firstWhere((m) => m.id == payee),
            amount: expense.amount,
          ),
        ],
      );
    } else {
      _replace(
        s,
        moved: (member) =>
            (expense.payers[member] ?? Paise.zero) -
            expense.splits
                .where((x) => x.memberId == member)
                .fold(Paise.zero, (sum, x) => sum + x.amount),
      );
    }
    return id;
  }

  /// The payee of your pending settle-up in [spaceId] confirms it, which
  /// moves the balances, or disputes it, which drops it.
  void answer(String spaceId, String payeeId, {required bool confirmed}) {
    final s = spaces.spaces.firstWhere((s) => s.id == spaceId);
    final p = s.pendingFromYou.firstWhere((p) => p.to.id == payeeId);
    _replace(
      s,
      pending: [
        for (final q in s.pendingFromYou)
          if (q != p) q,
      ],
      moved: (member) => !confirmed
          ? Paise.zero
          : member == p.from.id
          ? p.amount
          : member == p.to.id
          ? Paise.zero - p.amount
          : Paise.zero,
    );
  }

  void _replace(
    SpaceSummary s, {
    List<Payment<SpaceMember>>? pending,
    Paise Function(String member)? moved,
  }) {
    SpaceMember move(SpaceMember m) => SpaceMember(
      id: m.id,
      name: m.name,
      phone: m.phone,
      isYou: m.isYou,
      balance: m.balance + (moved?.call(m.id) ?? Paise.zero),
      upiId: m.upiId,
    );
    final members = [for (final m in s.members) move(m)];
    SpaceMember now(SpaceMember m) => members.firstWhere((x) => x.id == m.id);
    final list = spaces.spaces;
    list[list.indexOf(s)] = SpaceSummary(
      id: s.id,
      name: s.name,
      kind: s.kind,
      hasExpenses: s.hasExpenses,
      departed: s.departed,
      members: members,
      pendingFromYou: [
        for (final p in pending ?? s.pendingFromYou)
          (from: now(p.from), to: now(p.to), amount: p.amount),
      ],
    );
  }
}
