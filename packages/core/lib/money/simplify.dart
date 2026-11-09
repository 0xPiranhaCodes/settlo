import 'package:settlo_core/money/paise.dart';

/// One settling payment: `from` pays `to` the given `amount`.
typedef Payment<T> = ({T from, T to, Paise amount});

/// Turns per-member net balances into the payments that settle them.
///
/// [nets] maps each member to their net balance: positive means the member
/// is owed money (creditor), negative means they owe (debtor). Nets must sum
/// to zero, otherwise [ArgumentError] is thrown.
///
/// Greedy: repeatedly the largest debtor pays the largest creditor
/// `min(debt, credit)`. Ties between equal balances go to the member that
/// comes first in [nets] iteration order, so the result is deterministic.
/// Every payment zeroes at least one member and the last zeroes two, so there
/// are at most `n - 1` payments for `n` members with a non-zero net.
List<Payment<T>> simplifyDebts<T>(Map<T, Paise> nets) {
  if (nets.values.fold<int>(0, (s, p) => s + p.value) != 0) {
    throw ArgumentError.value(nets, 'nets', 'must sum to zero');
  }
  final balances = {
    for (final e in nets.entries)
      if (e.value.value != 0) e.key: e.value.value,
  };
  final payments = <Payment<T>>[];
  while (balances.isNotEmpty) {
    late T debtor;
    late T creditor;
    var debt = 0;
    var credit = 0;
    for (final MapEntry(:key, :value) in balances.entries) {
      if (-value > debt) (debtor, debt) = (key, -value);
      if (value > credit) (creditor, credit) = (key, value);
    }
    final amount = debt < credit ? debt : credit;
    payments.add((from: debtor, to: creditor, amount: Paise(amount)));
    balances
      ..[debtor] = balances[debtor]! + amount
      ..[creditor] = balances[creditor]! - amount
      ..removeWhere((_, v) => v == 0);
  }
  return payments;
}
