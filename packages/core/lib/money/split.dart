import 'package:settlo_core/money/paise.dart';

/// Splits [amount] equally between [members] (ADR 0003).
///
/// Every member gets `amount ~/ members.length` paise and the whole
/// remainder `amount % members.length` goes to the [payer]. If the payer is
/// not in [members], the remainder goes to the first member in the given
/// order. So 10001 paise between A, B, C paid by C is A 3333, B 3333,
/// C 3335.
///
/// Preconditions, each enforced with an [ArgumentError]: [amount] is not
/// negative (refunds are settlements, not negative splits) and [members] is
/// non-empty and unique. The result preserves the order of [members].
Map<T, Paise> splitEqual<T>(Paise amount, List<T> members, {required T payer}) {
  _checkAmount(amount);
  if (members.isEmpty || members.toSet().length != members.length) {
    throw ArgumentError.value(members, 'members', 'must be non-empty, unique');
  }
  final share = amount.value ~/ members.length;
  final taker = members.contains(payer) ? payer : members.first;
  return {
    for (final m in members)
      m: Paise(m == taker ? share + amount.value % members.length : share),
  };
}

/// Uses [shares] as-is.
///
/// Preconditions, each enforced with an [ArgumentError]: [amount] and every
/// share are not negative, and the shares sum to [amount].
Map<T, Paise> splitExact<T>(Paise amount, Map<T, Paise> shares) {
  _checkAmount(amount);
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
/// discarded fraction; ties go to the [payer] first, then map order. A
/// member with 0 bp never receives a paisa.
///
/// Preconditions, each enforced with an [ArgumentError]: [amount] and every
/// weight are not negative.
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
/// [splitPercent].
///
/// Preconditions, each enforced with an [ArgumentError]: [amount] and every
/// share are not negative, and the shares have a positive total.
Map<T, Paise> splitShares<T>(
  Paise amount,
  Map<T, int> shares, {
  required T payer,
}) => _allocate(amount, shares, payer);

/// Largest-remainder allocation; ties go in payer-first, then map order.
Map<T, Paise> _allocate<T>(Paise amount, Map<T, int> weights, T payer) {
  _checkAmount(amount);
  final total = weights.values.fold<int>(0, (s, w) => s + w);
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

/// v1 splits never carry negative amounts; refunds are settlements.
void _checkAmount(Paise amount) {
  if (amount.value < 0) {
    throw ArgumentError.value(amount, 'amount', 'must not be negative');
  }
}
