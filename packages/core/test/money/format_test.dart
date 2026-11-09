import 'package:flutter_test/flutter_test.dart';
import 'package:settlo_core/settlo_core.dart';

void main() {
  group('formatInr', () {
    test('uses Indian grouping', () {
      expect(formatInr(Paise.zero), '₹0');
      expect(formatInr(const Paise.rupees(420)), '₹420');
      expect(formatInr(const Paise.rupees(1000)), '₹1,000');
      expect(formatInr(const Paise.rupees(674200)), '₹6,74,200');
      expect(formatInr(const Paise.rupees(1000000)), '₹10,00,000');
      expect(formatInr(const Paise.rupees(123456789)), '₹12,34,56,789');
    });

    test('shows paise only when non-zero', () {
      expect(formatInr(const Paise(42050)), '₹420.50');
      expect(formatInr(const Paise(5)), '₹0.05');
    });

    test('sign', () {
      expect(formatInr(const Paise(-67420000)), '-₹6,74,200');
      expect(formatInr(const Paise.rupees(420), signed: true), '+₹420');
      expect(formatInr(Paise.zero, signed: true), '₹0');
    });
  });

  test('parseInr reads typed rupees straight into paise', () {
    expect(parseInr('1,800'), const Paise.rupees(1800));
    expect(parseInr(' 420.5 '), const Paise(42050));
    expect(parseInr('0.05'), const Paise(5));
    expect(parseInr('12.'), const Paise.rupees(12));
    for (final bad in ['', '.5', '1.234', '-1', '1e3', '₹10']) {
      expect(parseInr(bad), isNull, reason: bad);
    }
  });

  test('spokenInr says rupees in words with the sign, never paise', () {
    expect(
      spokenInr(const Paise.rupees(4200)),
      'four thousand two hundred rupees',
    );
    expect(
      spokenInr(const Paise(-365000)),
      'minus three thousand six hundred fifty rupees',
    );
    expect(
      spokenInr(const Paise.rupees(674200), signed: true),
      'plus six lakh seventy-four thousand two hundred rupees',
    );
    expect(spokenInr(Paise.zero, signed: true), 'zero rupees');
    expect(
      spokenInr(const Paise(42050)),
      'four hundred twenty rupees and fifty paise',
    );
  });

  group('amountInWords', () {
    test('Indian system', () {
      expect(amountInWords(const Paise.rupees(1000000)), 'ten lakh rupees');
      expect(
        amountInWords(const Paise.rupees(674200)),
        'six lakh seventy-four thousand two hundred rupees',
      );
      expect(
        amountInWords(const Paise.rupees(250000000)),
        'twenty-five crore rupees',
      );
      expect(
        amountInWords(const Paise.rupees(1000000000)),
        'one hundred crore rupees',
      );
      expect(
        amountInWords(const Paise.rupees(115)),
        'one hundred fifteen rupees',
      );
      expect(amountInWords(const Paise.rupees(90)), 'ninety rupees');
    });

    test('lakh and crore boundaries', () {
      for (final (rupees, words) in [
        (99999, 'ninety-nine thousand nine hundred ninety-nine'),
        (100000, 'one lakh'),
        (100001, 'one lakh one'),
        (
          9999999,
          'ninety-nine lakh ninety-nine thousand nine hundred ninety-nine',
        ),
        (10000000, 'one crore'),
        (10000001, 'one crore one'),
        (10100000, 'one crore one lakh'),
      ]) {
        expect(amountInWords(Paise.rupees(rupees)), '$words rupees');
      }
      expect(
        amountInWords(const Paise(1000000001)),
        'one crore rupees and one paisa',
      );
      expect(
        amountInWords(const Paise(10000099)),
        'one lakh rupees and ninety-nine paise',
      );
    });

    test('singular, zero and paise', () {
      expect(amountInWords(Paise.zero), 'zero rupees');
      expect(amountInWords(const Paise.rupees(1)), 'one rupee');
      expect(amountInWords(const Paise(1)), 'one paisa');
      expect(amountInWords(const Paise(50)), 'fifty paise');
      expect(
        amountInWords(const Paise(125050)),
        'one thousand two hundred fifty rupees and fifty paise',
      );
    });

    test('rejects negatives', () {
      expect(() => amountInWords(const Paise(-1)), throwsArgumentError);
    });
  });

  test('Paise arithmetic', () {
    expect(const Paise(5) + const Paise(3), const Paise(8));
    expect(const Paise(5) - const Paise(8), const Paise(-3));
    expect(-const Paise(5), const Paise(-5));
  });
}
