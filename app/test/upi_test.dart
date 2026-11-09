import 'package:flutter_test/flutter_test.dart';
import 'package:settlo_core/settlo_core.dart';
import 'package:settlo_settle/settlo_settle.dart';

void main() {
  group('upiAmount', () {
    test('is rupees with exactly two decimals from integer paise', () {
      for (final (paise, rupees) in [
        (1, '0.01'),
        (10, '0.10'),
        (99, '0.99'),
        (100, '1.00'),
        (365000, '3650.00'),
        (42050, '420.50'),
        (999999999, '9999999.99'), // ₹99,99,999.99
      ]) {
        expect(upiAmount(Paise(paise)), rupees, reason: '$paise paise');
      }
    });

    test('refuses zero and negative amounts', () {
      expect(() => upiAmount(Paise.zero), throwsArgumentError);
      expect(() => upiAmount(const Paise(-100)), throwsArgumentError);
    });
  });

  group('upiPayUri', () {
    test('prefills payee, name, amount, INR and note in order', () {
      final uri = upiPayUri(
        payee: 'kabir@oksbi',
        name: 'Kabir',
        amount: const Paise.rupees(3650),
        note: 'Settlo: Goa trip',
      );
      expect(
        uri.toString(),
        'upi://pay?pa=kabir%40oksbi&pn=Kabir&am=3650.00&cu=INR'
        '&tn=Settlo%3A%20Goa%20trip',
      );
      expect((uri.scheme, uri.host), ('upi', 'pay'));
    });

    test('encodes spaces as %20 and & so names cannot add fields', () {
      final uri = upiPayUri(
        payee: 'r.k-1@ybl',
        name: 'Rahul & Sons Pvt',
        amount: const Paise(1),
        note: 'Flat 402 & co=1',
      );
      final s = uri.toString();
      expect(s, isNot(contains('+')));
      expect(s, contains('pn=Rahul%20%26%20Sons%20Pvt'));
      expect(s, contains('am=0.01'));
      expect(uri.queryParameters, {
        'pa': 'r.k-1@ybl',
        'pn': 'Rahul & Sons Pvt',
        'am': '0.01',
        'cu': 'INR',
        'tn': 'Flat 402 & co=1',
      });
    });

    test('the largest amount keeps its paise', () {
      final uri = upiPayUri(
        payee: 'a@b',
        name: 'A',
        amount: const Paise(999999999),
        note: 'n',
      );
      expect(uri.queryParameters['am'], '9999999.99');
    });
  });
}
