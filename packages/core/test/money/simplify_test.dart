import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:settlo_core/settlo_core.dart';

void main() {
  test('largest debtor pays largest creditor', () {
    final payments = simplifyDebts({
      'a': const Paise(500),
      'b': const Paise(-300),
      'c': const Paise(-200),
    });
    expect(payments, [
      (from: 'b', to: 'a', amount: const Paise(300)),
      (from: 'c', to: 'a', amount: const Paise(200)),
    ]);
  });

  test('ties break by member order', () {
    final payments = simplifyDebts({
      'a': const Paise(-100),
      'b': const Paise(-100),
      'c': const Paise(100),
      'd': const Paise(100),
    });
    expect(payments, [
      (from: 'a', to: 'c', amount: const Paise(100)),
      (from: 'b', to: 'd', amount: const Paise(100)),
    ]);
  });

  test('settled group needs no payments', () {
    expect(simplifyDebts({'a': Paise.zero, 'b': Paise.zero}), isEmpty);
  });

  test('rejects nets that do not sum to zero', () {
    expect(() => simplifyDebts({'a': const Paise(1)}), throwsArgumentError);
  });

  test('property: payments zero every net in at most n-1 steps', () {
    final rng = Random(7);
    for (var i = 0; i < 2000; i++) {
      final n = rng.nextInt(15) + 1;
      final nets = <String, int>{
        for (var m = 0; m < n - 1; m++) 'm$m': rng.nextInt(200001) - 100000,
      };
      nets['m${n - 1}'] = -nets.values.fold<int>(0, (s, v) => s + v);

      final payments = simplifyDebts(nets.map((k, v) => MapEntry(k, Paise(v))));

      final nonZero = nets.values.where((v) => v != 0).length;
      expect(payments.length, lessThanOrEqualTo(max(0, nonZero - 1)));
      expect(payments.length, lessThanOrEqualTo(max(0, n - 1)));
      final left = Map.of(nets);
      for (final p in payments) {
        expect(p.amount.value, greaterThan(0));
        left[p.from] = left[p.from]! + p.amount.value;
        left[p.to] = left[p.to]! - p.amount.value;
      }
      expect(left.values.every((v) => v == 0), isTrue, reason: '$nets');
    }
  });
}
