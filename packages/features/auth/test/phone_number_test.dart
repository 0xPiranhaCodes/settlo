import 'package:flutter_test/flutter_test.dart';
import 'package:settlo_auth/settlo_auth.dart';

void main() {
  const india = Country.india;
  final uae = Country.all.firstWhere((c) => c.iso == 'AE');

  group('E.164', () {
    test('accepts Indian mobiles starting 6 to 9', () {
      expect(india.e164('9876543210'), '+919876543210');
      expect(india.e164('98765 43210'), '+919876543210');
      expect(india.e164('6000000000'), '+916000000000');
      expect(india.e164('9000000001'), '+919000000001');
    });

    test('strips a pasted country code or trunk zero', () {
      expect(india.e164('+91 98765 43210'), '+919876543210');
      expect(india.e164('919876543210'), '+919876543210');
      expect(india.e164('098765 43210'), '+919876543210');
    });

    test('rejects numbers that cannot be Indian mobiles', () {
      for (final input in [
        '',
        '98765',
        '987654321',
        '98765432101',
        '5876543210',
        '1234567890',
        '+1 98765 43210',
      ]) {
        expect(india.e164(input), isNull, reason: input);
      }
    });

    test('accepts other countries by length, up to 15 digits in all', () {
      expect(uae.e164('501234567'), '+971501234567');
      expect(uae.e164('12345'), isNull);
      expect(uae.e164('1234567890123'), isNull);
    });
  });

  test('display groups Indian numbers 5 and 5', () {
    expect(india.display('+919876543210'), '+91 98765 43210');
    expect(india.label, 'IN +91');
    expect(uae.display('+971501234567'), '+971 501234567');
  });

  group('NationalNumberFormatter', () {
    String format(String input, [Country country = india]) =>
        NationalNumberFormatter(country)
            .formatEditUpdate(
              TextEditingValue.empty,
              TextEditingValue(text: input),
            )
            .text;

    test('groups as typed and caps at ten digits', () {
      expect(format('98765'), '98765');
      expect(format('987654'), '98765 4');
      expect(format('987654321099'), '98765 43210');
    });

    test('cleans a pasted number', () {
      expect(format('+91 98765-43210'), '98765 43210');
      expect(format('098765 43210'), '98765 43210');
    });
  });
}
