import 'package:flutter_test/flutter_test.dart';
import 'package:settlo_core/settlo_core.dart';

import 'fixtures.dart';

/// An expected line from its fields, already quoted where needed.
String _row(List<Object> fields) => fields.join(',');

void main() {
  final csv = spaceCsv(flat(), flatLedger());
  final lines = csv.substring(1).split('\r\n');

  test('starts with a BOM and a header, and ends each line with CRLF', () {
    expect(csv.codeUnitAt(0), 0xFEFF);
    expect(csv.endsWith('\r\n'), isTrue);
    expect(
      lines.first,
      _row(const [
        'entry', 'date', 'description', 'category', 'settlement', //
        'settlement_status', 'total_paise', 'total_rupees', 'member',
        'paid_paise', 'paid_rupees', 'share_paise', 'share_rupees',
      ]),
    );
  });

  test('lists oldest first, one row per member, in paise and rupees', () {
    const rent = [1, '2026-11-01', 'Rent', '', 'no', '', 4200000, '42000.00'];
    expect(lines.sublist(1, 4), [
      _row([...rent, 'Sana', 0, '0.00', 1400000, '14000.00']),
      _row([...rent, 'Member 4', 0, '0.00', 1400000, '14000.00']),
      _row([...rent, 'Ravi', 4200000, '42000.00', 1400000, '14000.00']),
    ]);
  });

  test('gives the remainder paise to the payer and quotes commas and '
      'quotes', () {
    const dinner = [
      2, '2026-11-02', '"Dinner, ""Truffles"" & dessert"', 'food', 'no', '', //
      10001, '100.01',
    ];
    expect(lines.sublist(4, 7), [
      _row([...dinner, 'Sana', 0, '0.00', 3333, '33.33']),
      _row([...dinner, 'प्रिया', 10001, '100.01', 3335, '33.35']),
      _row([...dinner, 'Zoë', 0, '0.00', 3333, '33.33']),
    ]);
  });

  test('flags settle-ups with their status and defuses formulas', () {
    const link = [
      3, '2026-11-08', '"\'=HYPERLINK(""x"")"', '', 'yes', 'confirmed', //
      50000, '500.00',
    ];
    const settle = [
      4, '2026-11-09', 'Settle up', '', 'yes', 'pending', 3333, '33.33', //
    ];
    expect(lines.sublist(7, 11), [
      _row([...link, 'प्रिया', 0, '0.00', 50000, '500.00']),
      _row([...link, 'Zoë', 50000, '500.00', 0, '0.00']),
      _row([...settle, 'प्रिया', 0, '0.00', 3333, '33.33']),
      _row([...settle, 'Sana', 3333, '33.33', 0, '0.00']),
    ]);
    expect(lines, hasLength(12));
    expect(lines.last, isEmpty);
  });

  test('never writes a phone number', () {
    expect(csv, isNot(contains('98000')));
  });
}
