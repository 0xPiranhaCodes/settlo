import 'package:settlo_core/money/paise.dart';

/// Splits [amount] equally between [members].
///
/// Each member gets `amount ~/ members.length` paise. The remainder `r`
/// (always fewer paise than members) is handed out one paisa each to the
/// first `r` members in *payer-first order*: the [payer] first (if they are a
/// member), then the remaining members in the order given. So ₹100 between
/// A, B, C paid by B is B 33.34, A 33.33, C 33.33.
///
/// The result preserves the order of [members]. Throws [ArgumentError] if
/// [amount] is negative or [members] is empty or has duplicates.
Map<T, Paise> splitEqual<T>(Paise amount, List<T> members, {required T payer}) {
  final weights = {for (final m in members) m: 1};
  if (weights.length != members.length) {
    throw ArgumentError.value(members, 'members', 'must be unique');
  }
  return _allocate(amount, weights, payer);
}

/// Uses [shares] as-is after checking they are non-negative and sum to
/// [amount]; throws [ArgumentError] otherwise.
Map<T, Paise> splitExact<T>(Paise amount, Map<T, Paise> shares) {
  final sum = shares.values.fold<int>(0, (s, p) => s + p.value);
  if (shares.values.any((p) => p.value < 0) || sum != amount.value) {
    throw ArgumentError.value(
      shares,
      'shares',
      'must be non-negative and sum to ${amount.value}',
    );
  }
  return Map.of(shares);
}

/// Splits [amount] by percentage given in basis points (1% = 100 bp).
///
/// [basisPoints] must be non-negative and sum to exactly 10000. Each member
/// first gets `floor(amount * bp / 10000)`; the leftover paise (fewer than
/// the number of members) go one each to the members with the largest
/// discarded fraction, ties broken in payer-first order as in [splitEqual].
/// A member with 0 bp never receives a paisa.
Map<T, Paise> splitPercent<T>(
  Paise amount,
  Map<T, int> basisPoints, {
  required T payer,
}) {
  final total = basisPoints.values.fold<int>(0, (s, w) => s + w);
  if (total != 10000) {
    throw ArgumentError.value(basisPoints, 'basisPoints', 'must sum to 10000');
  }
  return _allocate(amount, basisPoints, payer);
}

/// Splits [amount] in proportion to integer [shares] (e.g. 2 for a couple,
/// 1 for a single). Rounding follows the same largest-remainder rule as
/// [splitPercent]. Shares must be non-negative with a positive total.
Map<T, Paise> splitShares<T>(
  Paise amount,
  Map<T, int> shares, {
  required T payer,
}) => _allocate(amount, shares, payer);

/// Largest-remainder allocation; ties go in payer-first, then map order.
Map<T, Paise> _allocate<T>(Paise amount, Map<T, int> weights, T payer) {
  final total = weights.values.fold<int>(0, (s, w) => s + w);
  if (amount.value < 0) {
    throw ArgumentError.value(amount, 'amount', 'must be >= 0');
  }
  if (weights.values.any((w) => w < 0) || total <= 0) {
    throw ArgumentError.value(
      weights,
      'weights',
      'must be non-negative with a positive total',
    );
  }
  // shortcut: amount * weight must fit in int (fine below ~9e14 paise at
  // 10000 bp); switch to BigInt if shares ever get huge.
  final base = {
    for (final e in weights.entries) e.key: amount.value * e.value ~/ total,
  };
  final fraction = {
    for (final e in weights.entries) e.key: amount.value * e.value % total,
  };
  final order = [
    if (weights.containsKey(payer)) payer,
    ...weights.keys.where((k) => k != payer),
  ];
  // List.sort is not stable, so break ties on position explicitly.
  final rank = {for (var i = 0; i < order.length; i++) order[i]: i};
  order.sort((a, b) {
    final byFraction = fraction[b]!.compareTo(fraction[a]!);
    return byFraction != 0 ? byFraction : rank[a]!.compareTo(rank[b]!);
  });
  final left = amount.value - base.values.fold<int>(0, (s, v) => s + v);
  for (final k in order.take(left)) {
    base[k] = base[k]! + 1;
  }
  return {for (final k in weights.keys) k: Paise(base[k]!)};
}
