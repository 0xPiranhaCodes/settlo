import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:settlo_core/settlo_core.dart';

import 'fixtures.dart';

final _at = DateTime.utc(2026, 11, 10, 9, 34);

/// The number every adversarial field carries, in the forms people type.
const _forms = ['+91 98000 00009', '+919800000009', '98000-00009'];

/// Every digit of it, however it was spaced.
bool _leaks(String text) =>
    text.replaceAll(RegExp(r'[\s-]'), '').contains('9800000009');

SpaceSummary _flatNamed({String? space, String? label}) {
  final f = flat();
  return SpaceSummary(
    id: f.id,
    name: space ?? f.name,
    kind: f.kind,
    members: [
      for (final m in f.members)
        if (m.id == 'm3' && label != null)
          SpaceMember(id: m.id, name: label, phone: m.phone)
        else
          m,
    ],
    departed: f.departed,
  );
}

SpaceLedger _ledgerWith({String? description, String? category}) {
  final l = flatLedger();
  final e = l.expenses.last;
  return SpaceLedger(
    today: l.today,
    expenses: [
      ...l.expenses.take(l.expenses.length - 1),
      SpaceExpense(
        id: e.id,
        description: description ?? e.description,
        category: category ?? e.category,
        amount: e.amount,
        spentOn: e.spentOn,
        payers: e.payers,
        splits: e.splits,
      ),
    ],
  );
}

Loan _loan({String? counterparty, String? reference, String? disputeReason}) {
  final l = arjunLoan();
  return Loan(
    id: l.id,
    counterparty: counterparty ?? l.counterparty,
    youLent: l.youLent,
    principal: l.principal,
    repaid: l.repaid,
    startOn: l.startOn,
    repayments: [
      LoanRepayment(
        id: 'x',
        amount: const Paise.rupees(25000),
        paidOn: DateTime(2026, 11, 5),
        method: RepaymentMethod.upi,
        reference: reference,
        status: RepaymentStatus.disputed,
        recordedByYou: false,
        disputeReason: disputeReason,
      ),
    ],
  );
}

String _pdfText(Statement s) => statementTexts(s).join('\n');

void main() {
  test('redacts phone-like runs and leaves amounts and dates alone', () {
    for (final n in _forms) {
      expect(redactPhones('Call $n now'), 'Call •••• now');
    }
    expect(
      redactPhones('₹10,00,000 on 2026-11-05, ref 12345'),
      '₹10,00,000 on 2026-11-05, ref 12345',
    );
  });

  for (final n in _forms) {
    group('number written as "$n"', () {
      test('CSV: expense description', () {
        final csv = spaceCsv(flat(), _ledgerWith(description: 'Rent, ask $n'));
        expect(_leaks(csv), isFalse);
        expect(csv, contains('"Rent, ask ••••"'));
      });

      test('CSV: category', () {
        final csv = spaceCsv(flat(), _ledgerWith(category: 'via $n'));
        expect(_leaks(csv), isFalse);
        expect(csv, contains(',via ••••,'));
      });

      test('CSV and PDF: member label', () {
        final space = _flatNamed(label: 'Zoë $n');
        expect(_leaks(spaceCsv(space, flatLedger())), isFalse);
        final pdf = _pdfText(
          spaceSummary(space, flatLedger(), generatedAt: _at),
        );
        expect(_leaks(pdf), isFalse);
        expect(pdf, contains('Zoë ••••'));
      });

      test('PDF: space name', () {
        final pdf = _pdfText(
          spaceSummary(
            _flatNamed(space: 'Flat $n'),
            flatLedger(),
            generatedAt: _at,
          ),
        );
        expect(_leaks(pdf), isFalse);
        expect(pdf, contains('Flat ••••'));
      });

      test('PDF: loan counterparty and your name', () {
        final s = loanStatement(
          _loan(counterparty: 'Arjun $n'),
          generatedAt: _at,
          yourName: 'Sana $n',
        );
        expect(_leaks(_pdfText(s)), isFalse);
        expect(
          _pdfText(s),
          allOf(contains('Arjun ••••'), contains('Sana •••• (you)')),
        );
      });

      test('PDF: repayment reference', () {
        final s = loanStatement(_loan(reference: 'UTR $n'), generatedAt: _at);
        expect(_leaks(_pdfText(s)), isFalse);
        expect(_pdfText(s), contains('UPI · UTR ••••'));
      });

      test('PDF: dispute reason', () {
        final s = loanStatement(
          _loan(disputeReason: 'Call me on $n'),
          generatedAt: _at,
        );
        expect(_leaks(_pdfText(s)), isFalse);
        expect(_pdfText(s), contains('“Call me on ••••”'));
      });
    });
  }

  group('names the fonts cannot draw', () {
    final summary = spaceSummary(flat(), flatLedger(), generatedAt: _at);

    test('are found, and Latin text is not', () {
      expect(textsOutsideFonts(summary, fonts), {
        'प्रिया',
        'Sana, प्रिया, Zoë, Member 4',
      });
    });

    test('are embedded as images when drawn', () async {
      final png = base64.decode(
        'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mNk'
        'YPhfDwAChwGA60e6kgAAAABJRU5ErkJggg==',
      );
      final images = {
        for (final t in textsOutsideFonts(summary, fonts))
          t: (png: png, width: 30.0, height: 12.0),
      };
      final withImages = latin1.decode(
        await statementPdf(summary, fonts: fonts, images: images),
      );
      expect(RegExp(r'/Subtype\s*/Image').allMatches(withImages), isNotEmpty);

      final without = latin1.decode(await statementPdf(summary, fonts: fonts));
      expect(RegExp(r'/Subtype\s*/Image').hasMatch(without), isFalse);
    });
  });
}
