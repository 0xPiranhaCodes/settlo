import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:settlo_core/settlo_core.dart';

import 'fixtures.dart';

/// 10 Nov 2026, 3:04 pm in India.
final _at = DateTime.utc(2026, 11, 10, 9, 34);

T _block<T extends StatementBlock>(Statement s, [int skip = 0]) =>
    s.blocks.whereType<T>().elementAt(skip);

Map<String, Object> _values(StatementFacts facts) => {
  for (final f in facts.facts) f.label: f.value,
};

/// A table's rows as [cells, muted], which `equals` compares deeply.
List<List<Object>> _rows(Statement s) => [
  for (final r in _block<StatementTable>(s).rows) [r.cells, r.muted],
];

String _allText(Statement s) => statementTexts(s).join('\n');

const _r25k = Inr(Paise(2500000));

/// Serves the font files under the keys the app bundle uses.
final class _Bundle extends CachingAssetBundle {
  @override
  Future<ByteData> load(String key) async => ByteData.sublistView(
    File(key.replaceFirst('packages/settlo_core/', '')).readAsBytesSync(),
  );
}

void main() {
  test('IST stamp ignores the device zone', () {
    expect(istStamp(_at), '10 Nov 2026, 3:04 pm IST');
    expect(
      istStamp(DateTime.utc(2026, 11, 9, 18, 30)),
      '10 Nov 2026, 12:00 am IST',
    );
  });

  test('loads the bundled fonts by their package keys', () async {
    final fonts = await loadStatementFonts(_Bundle());
    final s = loanStatement(arjunLoan(), generatedAt: _at);
    expect(pdfPages(await statementPdf(s, fonts: fonts)), 1);
  });

  test('amounts compare by paise', () {
    expect(const Inr(Paise(5)).hashCode, const Inr(Paise(5)).hashCode);
    expect(const Inr(Paise(5)), isNot(const Inr(Paise(6))));
  });

  group('loan statement', () {
    final s = loanStatement(arjunLoan(), generatedAt: _at, yourName: 'Sana');

    test('names both sides and the terms', () {
      expect(s.title, 'Loan statement');
      expect(s.generated, '10 Nov 2026, 3:04 pm IST');
      final terms = _block<StatementFacts>(s);
      expect(_values(terms), {
        'Lender': 'Sana (you)',
        'Borrower': 'Arjun',
        'Principal': const Inr(Paise.rupees(1000000)),
        'Started': '5 Aug 2026',
        'Instalment': '₹25,000 monthly, on the 5th',
        'Schedule': '3 of 40 instalments repaid, ends Nov 2029',
        'Interest': 'Interest free',
      });
      expect(terms.facts[2].note, 'Ten lakh rupees');
    });

    test('counts only confirmed repayments; disputed are listed apart', () {
      final outstanding = _block<StatementTotal>(s);
      expect(outstanding.label, 'Outstanding');
      expect(outstanding.amount, const Paise(92500000));
      expect(outstanding.words, 'Nine lakh twenty-five thousand rupees');
      expect(_values(_block<StatementFacts>(s, 1)), {
        'Repaid': const Inr(Paise(7500000)),
        'Awaiting': const Inr(Paise(2500050)),
        'Disputed': _r25k,
      });

      expect(_rows(s), [
        [
          ['5 Aug 2026', 'Bank', 'Arjun', 'Confirmed', _r25k],
          false,
        ],
        [
          ['5 Sep 2026', 'Bank', 'Arjun', 'Confirmed', _r25k],
          false,
        ],
        [
          ['5 Oct 2026', 'Bank', 'Arjun', 'Confirmed', _r25k],
          false,
        ],
        [
          [
            '5 Nov 2026',
            'Cash',
            'Arjun',
            'Disputed, not counted: “Not received”',
            _r25k,
          ],
          true,
        ],
        [
          [
            '6 Nov 2026',
            'UPI · 4321 8812 0099',
            'Arjun',
            'Awaiting you',
            const Inr(Paise(2500050)),
          ],
          true,
        ],
      ]);
      final counted = _block<StatementTable>(s).rows
          .where((r) => !r.muted)
          .fold(0, (t, r) => t + (r.cells.last as Inr).paise.value);
      expect(counted, 7500000);
    });

    test('a counterparty known only by number is not printed', () {
      final loan = arjunLoan();
      final s = loanStatement(
        Loan(
          id: loan.id,
          counterparty: '+919800000009',
          youLent: false,
          principal: loan.principal,
          repaid: loan.repaid,
          startOn: loan.startOn,
          repayments: loan.repayments,
        ),
        generatedAt: _at,
      );
      final terms = _values(_block<StatementFacts>(s));
      expect(terms['Lender'], 'The other party');
      expect(terms['Borrower'], 'You (you)');
      expect(terms['Instalment'], 'Flexible, any amount');
      expect(_allText(s), isNot(contains('9800000009')));
    });

    test('renders a one-page PDF', () async {
      final pdf = await statementPdf(s, fonts: fonts);
      expect(latin1.decode(pdf.sublist(0, 5)), '%PDF-');
      expect(pdfPages(pdf), 1);
    });

    test('a long history runs over pages; none prints a note', () async {
      final loan = arjunLoan();
      Loan withRepayments(List<LoanRepayment> repayments, int dueDay) => Loan(
        id: loan.id,
        counterparty: loan.counterparty,
        youLent: loan.youLent,
        principal: loan.principal,
        repaid: loan.repaid,
        startOn: loan.startOn,
        installment: loan.installment,
        dueDay: dueDay,
        repayments: repayments,
      );
      final long = loanStatement(
        withRepayments([for (var i = 0; i < 90; i++) loan.repayments.last], 22),
        generatedAt: _at,
      );
      expect(
        _values(_block<StatementFacts>(long))['Instalment'],
        '₹25,000 monthly, on the 22nd',
      );
      expect(pdfPages(await statementPdf(long, fonts: fonts)), greaterThan(1));

      final none = loanStatement(withRepayments([], 13), generatedAt: _at);
      expect(
        _values(_block<StatementFacts>(none))['Instalment'],
        '₹25,000 monthly, on the 13th',
      );
      expect(_block<StatementTable>(none).empty, 'Nothing repaid yet.');
      expect(pdfPages(await statementPdf(none, fonts: fonts)), 1);
    });
  });

  group('space summary', () {
    final s = spaceSummary(flat(), flatLedger(), generatedAt: _at);

    test('totals spending without settle-ups, with words', () {
      expect(s.title, 'Space summary');
      expect(_values(_block<StatementFacts>(s)), {
        'Space': 'Flat 4B',
        'Members': 'Sana, प्रिया, Zoë, Member 4',
        'Period': '1 Nov 2026 to 9 Nov 2026',
        'Expenses': '2',
      });
      final total = _block<StatementTotal>(s);
      expect(total.amount, const Paise(4210001));
      expect(
        total.words,
        'Forty-two thousand one hundred rupees and one paisa',
      );
    });

    test('lists paid against share per member, by name only', () {
      const zero = Inr(Paise.zero);
      const rent = Inr(Paise(1400000));
      expect(_rows(s), [
        [
          ['Sana', zero, const Inr(Paise(1403333)), 'Owes ₹33.33'],
          false,
        ],
        [
          [
            'प्रिया',
            const Inr(Paise(10001)),
            const Inr(Paise(3335)),
            'Is owed ₹66.68',
          ],
          false,
        ],
        [
          ['Zoë', zero, const Inr(Paise(3333)), 'Owes ₹33.35'],
          false,
        ],
        [
          ['Member 4', zero, rent, 'Settled'],
          false,
        ],
        [
          ['Ravi', const Inr(Paise(4200000)), rent, 'Left the space'],
          true,
        ],
      ]);
      expect(_allText(s), isNot(contains('98000')));
    });

    test('counts settle-ups by status', () {
      final settleUps = _block<StatementFacts>(s, 1);
      expect(settleUps.heading, 'Settle-ups');
      expect(
        [for (final f in settleUps.facts) (f.label, f.value, f.note)],
        [
          ('Confirmed', const Inr(Paise(50000)), '1 settle-up, counted'),
          ('Awaiting', const Inr(Paise(3333)), '1 settle-up, not counted yet'),
          ('Disputed', const Inr(Paise.zero), '0 settle-ups, never counted'),
        ],
      );
    });

    test('renders a one-page PDF', () async {
      final pdf = await statementPdf(s, fonts: fonts);
      expect(latin1.decode(pdf.sublist(0, 5)), '%PDF-');
      expect(pdfPages(pdf), 1);
    });
  });
}
