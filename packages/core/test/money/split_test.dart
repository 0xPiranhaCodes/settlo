import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:settlo_core/settlo_core.dart';

int _sum(Map<String, Paise> m) => m.values.fold<int>(0, (s, p) => s + p.value);

void main() {
  group('splitEqual', () {
    test('whole remainder goes to the payer', () {
      expect(splitEqual(const Paise(1000), ['a', 'b', 'c'], payer: 'a'), {
        'a': const Paise(334),
        'b': const Paise(333),
        'c': const Paise(333),
      });
      // amount % n > 1: both leftover paise stay with the payer.
      expect(splitEqual(const Paise(1001), ['a', 'b', 'c'], payer: 'a'), {
        'a': const Paise(335),
        'b': const Paise(333),
        'c': const Paise(333),
      });
      expect(splitEqual(const Paise(10001), ['a', 'b', 'c'], payer: 'c'), {
        'a': const Paise(3333),
        'b': const Paise(3333),
        'c': const Paise(3335),
      });
    });

    test('payer outside the split: first member takes the remainder', () {
      expect(splitEqual(const Paise(11), ['a', 'b', 'c'], payer: 'z'), {
        'a': const Paise(5),
        'b': const Paise(3),
        'c': const Paise(3),
      });
    });

    test('preserves member order', () {
      final r = splitEqual(const Paise(7), ['c', 'a', 'b'], payer: 'b');
      expect(r.keys, ['c', 'a', 'b']);
    });

    test('rejects bad input', () {
      expect(
        () => splitEqual(const Paise(10), <String>[], payer: 'a'),
        throwsArgumentError,
      );
      expect(
        () => splitEqual(const Paise(10), ['a', 'a'], payer: 'a'),
        throwsArgumentError,
      );
      expect(
        () => splitEqual(const Paise(-1), ['a'], payer: 'a'),
        throwsArgumentError,
      );
    });
  });

  group('splitExact', () {
    test('returns shares that add up', () {
      final shares = {'a': const Paise(70), 'b': const Paise(30)};
      expect(splitExact(const Paise(100), shares), shares);
    });

    test('rejects mismatch or negatives', () {
      expect(
        () => splitExact(const Paise(100), {'a': const Paise(99)}),
        throwsArgumentError,
      );
      expect(
        () => splitExact(const Paise(100), {
          'a': const Paise(101),
          'b': const Paise(-1),
        }),
        throwsArgumentError,
      );
    });
  });

  group('splitPercent', () {
    test('largest remainder, ties payer first', () {
      // 33.33% / 33.33% / 33.34% of 100 paise -> 33.33, 33.33, 33.34 floors.
      expect(
        splitPercent(const Paise(100), {
          'a': 3333,
          'b': 3333,
          'c': 3334,
        }, payer: 'b'),
        {'a': const Paise(33), 'b': const Paise(33), 'c': const Paise(34)},
      );
      // Equal fractions: payer b takes the leftover paisa.
      expect(
        splitPercent(const Paise(101), {'a': 5000, 'b': 5000}, payer: 'b'),
        {'a': const Paise(50), 'b': const Paise(51)},
      );
    });

    test('zero bp gets nothing', () {
      expect(
        splitPercent(const Paise(1), {
          'a': 0,
          'b': 5000,
          'c': 5000,
        }, payer: 'a'),
        {'a': Paise.zero, 'b': const Paise(1), 'c': Paise.zero},
      );
    });

    test('rejects totals other than 10000', () {
      expect(
        () => splitPercent(const Paise(100), {'a': 9999}, payer: 'a'),
        throwsArgumentError,
      );
    });
  });

  group('splitShares', () {
    test('proportional', () {
      expect(splitShares(const Paise(900), {'a': 2, 'b': 1}, payer: 'a'), {
        'a': const Paise(600),
        'b': const Paise(300),
      });
    });

    test('rejects zero or negative weights', () {
      expect(
        () => splitShares(const Paise(10), {'a': 0}, payer: 'a'),
        throwsArgumentError,
      );
      expect(
        () => splitShares(const Paise(10), {'a': 2, 'b': -1}, payer: 'a'),
        throwsArgumentError,
      );
    });
  });

  group('negative amounts are rejected', () {
    test('every split API', () {
      expect(
        () => splitEqual(const Paise(-10), ['a', 'b', 'c'], payer: 'b'),
        throwsArgumentError,
      );
      expect(
        () => splitExact(const Paise(-10), {
          'a': const Paise(-6),
          'b': const Paise(-4),
        }),
        throwsArgumentError,
      );
      expect(
        () =>
            splitPercent(const Paise(-101), {'a': 5000, 'b': 5000}, payer: 'a'),
        throwsArgumentError,
      );
      expect(
        () => splitShares(const Paise(-10), {'a': 2, 'b': 1}, payer: 'z'),
        throwsArgumentError,
      );
    });

    test('negative weights', () {
      expect(
        () => splitPercent(const Paise(10), {'a': 10001, 'b': -1}, payer: 'a'),
        throwsArgumentError,
      );
    });
  });

  test('property: every split sums to the amount', () {
    final rng = Random(12);
    for (var i = 0; i < 2000; i++) {
      final n = rng.nextInt(12) + 1;
      final members = [for (var m = 0; m < n; m++) 'm$m'];
      final payer = members[rng.nextInt(n)];
      final amount = Paise(rng.nextInt(1 << 30));

      final equal = splitEqual(amount, members, payer: payer);
      expect(_sum(equal), amount.value);
      for (final MapEntry(:key, :value) in equal.entries) {
        if (key != payer) expect(value.value, amount.value ~/ n);
      }
      expect(equal[payer]!.value, amount.value ~/ n + amount.value % n);

      final shares = {for (final m in members) m: rng.nextInt(5) + 1};
      expect(_sum(splitShares(amount, shares, payer: payer)), amount.value);

      final cuts = [for (var m = 1; m < n; m++) rng.nextInt(10001)]..sort();
      final edges = [0, ...cuts, 10000];
      final bp = {
        for (var m = 0; m < n; m++) members[m]: edges[m + 1] - edges[m],
      };
      expect(_sum(splitPercent(amount, bp, payer: payer)), amount.value);
    }
  });
}
