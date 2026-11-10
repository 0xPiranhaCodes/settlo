import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:settlo_core/export/names.dart';
import 'package:settlo_core/money/format.dart';
import 'package:settlo_core/money/paise.dart';
import 'package:settlo_core/supabase/home.dart';
import 'package:settlo_core/supabase/loans.dart';
import 'package:settlo_core/supabase/space_ledger.dart';
import 'package:settlo_core/supabase/spaces.dart';

/// The bundled fonts a statement embeds (ADR 0006), so ₹ and any name
/// render the same everywhere.
typedef StatementFonts = ({pw.Font regular, pw.Font medium, pw.Font serif});

/// Loads [StatementFonts] from the app's asset bundle.
Future<StatementFonts> loadStatementFonts([AssetBundle? bundle]) async {
  final b = bundle ?? rootBundle;
  Future<pw.Font> font(String file) async =>
      pw.Font.ttf(await b.load('packages/settlo_core/assets/fonts/$file'));
  return (
    regular: await font('Figtree-Regular.ttf'),
    medium: await font('Figtree-Medium.ttf'),
    serif: await font('IBMPlexSerif-Medium.ttf'),
  );
}

/// An amount in a statement, printed as INR with Indian grouping.
@immutable
final class Inr {
  /// [paise] as printed.
  const new(this.paise);

  /// The amount.
  final Paise paise;

  @override
  bool operator ==(Object other) => other is Inr && other.paise == paise;

  @override
  int get hashCode => paise.hashCode;

  @override
  String toString() => formatInr(paise);
}

/// A label, its value (text or [Inr]) and an optional note under it.
typedef StatementFact = ({String label, Object value, String? note});

/// A table row of text and [Inr] cells. A muted row prints in the
/// secondary colour: it is not counted (pending or disputed), or the
/// member has left.
typedef StatementRow = ({List<Object> cells, bool muted});

/// A part of a [Statement].
sealed class StatementBlock {
  const new();
}

/// Labelled lines, under an optional heading.
final class StatementFacts extends StatementBlock {
  /// [facts] under [heading].
  const new(this.facts, {this.heading});

  /// The lines.
  final List<StatementFact> facts;

  /// The heading, if any.
  final String? heading;
}

/// A total, printed large with its amount in words.
final class StatementTotal extends StatementBlock {
  /// [amount] labelled [label].
  const new(this.label, this.amount);

  /// What it totals.
  final String label;

  /// The total.
  final Paise amount;

  /// [amount] in words, as printed: `Ten lakh rupees`.
  String get words => _words(amount);
}

/// A table under [heading]; [empty] stands in for no [rows].
final class StatementTable extends StatementBlock {
  /// A table.
  const new({
    required this.heading,
    required this.header,
    required this.rows,
    this.empty = '',
  });

  /// The table's heading.
  final String heading;

  /// Column names; the last column is right-aligned.
  final List<String> header;

  /// The rows, in print order.
  final List<StatementRow> rows;

  /// What prints when there are no rows.
  final String empty;
}

/// What a statement PDF prints, before layout, so its content can be
/// checked without reading the PDF back.
@immutable
final class Statement {
  /// A statement.
  const new({
    required this.title,
    required this.generated,
    required this.blocks,
  });

  /// `Loan statement` or `Space summary`.
  final String title;

  /// When it was made, in IST ([istStamp]).
  final String generated;

  /// Its parts, in print order.
  final List<StatementBlock> blocks;
}

/// [loan]'s statement: who, the terms, what is outstanding and every
/// repayment, oldest first, with its status; dated [generatedAt] in IST.
///
/// Only confirmed repayments count. Pending and disputed ones are listed,
/// muted, but never added to a total. [yourName] names your side; the
/// other side is named, never numbered.
Statement loanStatement(
  Loan loan, {
  required DateTime generatedAt,
  String? yourName,
}) {
  final you = '${_named(yourName, 'You')} (you)';
  final them = _named(loan.counterparty, 'The other party');
  final (lender, borrower) = loan.youLent ? (you, them) : (them, you);
  Paise sum(RepaymentStatus status) => loan.repayments
      .where((r) => r.status == status)
      .fold(Paise.zero, (t, r) => t + r.amount);
  final pending = sum(RepaymentStatus.pending);
  final disputed = sum(RepaymentStatus.disputed);
  final installment = loan.installment;
  return Statement(
    title: 'Loan statement',
    generated: istStamp(generatedAt),
    blocks: [
      StatementFacts([
        (label: 'Lender', value: lender, note: null),
        (label: 'Borrower', value: borrower, note: null),
        (
          label: 'Principal',
          value: Inr(loan.principal),
          note: _words(loan.principal),
        ),
        (label: 'Started', value: _day(loan.startOn), note: null),
        (
          label: 'Instalment',
          value: installment == null
              ? 'Flexible, any amount'
              : '${formatInr(installment)} monthly, on the '
                    '${_ordinal(loan.dueDay ?? 1)}',
          note: null,
        ),
        if (loan.installmentsTotal case final total?)
          (
            label: 'Schedule',
            value: [
              '${loan.installmentsPaid ?? 0} of $total instalments repaid',
              if (loan.endsOn case final ends?) 'ends ${_month(ends)}',
            ].join(', '),
            note: null,
          ),
        (label: 'Interest', value: 'Interest free', note: null),
      ]),
      StatementTotal('Outstanding', loan.outstanding),
      StatementFacts([
        (
          label: 'Repaid',
          value: Inr(loan.repaid),
          note: 'Confirmed by both of you',
        ),
        if (pending != Paise.zero)
          (
            label: 'Awaiting',
            value: Inr(pending),
            note: 'Not counted until confirmed',
          ),
        if (disputed != Paise.zero)
          (label: 'Disputed', value: Inr(disputed), note: 'Never counted'),
      ]),
      StatementTable(
        heading: 'Repayments',
        header: const ['Paid on', 'How', 'Recorded by', 'Status', 'Amount'],
        empty: 'Nothing repaid yet.',
        rows: [
          for (final r in loan.repayments.reversed)
            (
              cells: [
                _day(r.paidOn),
                [r.method?.label ?? 'Repayment', ?r.reference].join(' · '),
                if (r.recordedByYou) 'You' else them,
                switch (r.status) {
                  RepaymentStatus.confirmed => 'Confirmed',
                  RepaymentStatus.pending =>
                    'Awaiting ${r.recordedByYou ? them : 'you'}',
                  RepaymentStatus.disputed =>
                    'Disputed, not counted'
                        '${r.disputeReason == null ? '' : ': '
                                  '“${r.disputeReason}”'}',
                },
                Inr(r.amount),
              ],
              muted: r.status != RepaymentStatus.confirmed,
            ),
        ],
      ),
    ],
  );
}

/// [space]'s summary: total spending, what each member paid against their
/// share, balances now and settle-ups; dated [generatedAt] in IST. The CSV
/// export (`spaceCsv`) carries every expense.
///
/// Settle-ups move balances but are not spending; pending and disputed
/// ones are listed but never counted. Members are named, never numbered.
Statement spaceSummary(
  SpaceSummary space,
  SpaceLedger ledger, {
  required DateTime generatedAt,
}) {
  final everyone = [...space.members, ...space.departed];
  final names = exportNames(everyone);
  final spending = ledger.expenses.where((e) => !e.isSettlement).toList();
  final paid = <String, Paise>{};
  final share = <String, Paise>{};
  for (final e in spending) {
    for (final p in e.payers) {
      paid[p.memberId] = (paid[p.memberId] ?? Paise.zero) + p.amount;
    }
    for (final x in e.splits) {
      share[x.memberId] = (share[x.memberId] ?? Paise.zero) + x.amount;
    }
  }
  StatementFact settled(String label, SettlementStatus status, String note) {
    final these = ledger.expenses.where(
      (e) => e.isSettlement && e.settlementStatus == status,
    );
    return (
      label: label,
      value: Inr(these.fold(Paise.zero, (t, e) => t + e.amount)),
      note: '${these.length} settle-up${these.length == 1 ? '' : 's'}, $note',
    );
  }

  final dates = [for (final e in ledger.expenses) e.spentOn]..sort();
  return Statement(
    title: 'Space summary',
    generated: istStamp(generatedAt),
    blocks: [
      StatementFacts([
        (label: 'Space', value: space.name, note: _kind(space.kind)),
        (
          label: 'Members',
          value: [for (final m in space.members) names[m.id]].join(', '),
          note: null,
        ),
        if (dates.isNotEmpty)
          (
            label: 'Period',
            value: '${_day(dates.first)} to ${_day(dates.last)}',
            note: null,
          ),
        (
          label: 'Expenses',
          value: '${spending.length}',
          note: 'Settle-ups not included',
        ),
      ]),
      StatementTotal(
        'Total spent',
        spending.fold(Paise.zero, (t, e) => t + e.amount),
      ),
      StatementTable(
        heading: 'Members',
        header: const ['Member', 'Paid', 'Fair share', 'Balance now'],
        rows: [
          for (final m in everyone)
            (
              cells: [
                names[m.id]!,
                Inr(paid[m.id] ?? Paise.zero),
                Inr(share[m.id] ?? Paise.zero),
                if (!space.members.contains(m))
                  'Left the space'
                else if (m.balance.value > 0)
                  'Is owed ${formatInr(m.balance)}'
                else if (m.balance.value < 0)
                  'Owes ${formatInr(-m.balance)}'
                else
                  'Settled',
              ],
              muted: !space.members.contains(m),
            ),
        ],
      ),
      StatementFacts(heading: 'Settle-ups', [
        settled('Confirmed', SettlementStatus.confirmed, 'counted'),
        settled('Awaiting', SettlementStatus.pending, 'not counted yet'),
        settled('Disputed', SettlementStatus.disputed, 'never counted'),
      ]),
    ],
  );
}

/// [statement] as an A4 PDF in [fonts], made on device.
Future<Uint8List> statementPdf(
  Statement statement, {
  required StatementFonts fonts,
}) {
  final s = _Styles(fonts);
  final title = statement.title;
  final doc = pw.Document(title: title, creator: 'Settlo')
    ..addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.fromLTRB(48, 44, 48, 40),
        maxPages: 200,
        theme: pw.ThemeData.withFont(
          base: s.fonts.regular,
          bold: s.fonts.medium,
        ),
        header: (context) => context.pageNumber > 1
            ? pw.Padding(
                padding: const pw.EdgeInsets.only(bottom: 12),
                child: pw.Text(title, style: s.muted),
              )
            : pw.Padding(
                padding: const pw.EdgeInsets.only(bottom: 22),
                child: pw.Row(
                  crossAxisAlignment: pw.CrossAxisAlignment.end,
                  children: [
                    pw.Text('settlo', style: s.wordmark),
                    pw.Spacer(),
                    pw.Column(
                      crossAxisAlignment: pw.CrossAxisAlignment.end,
                      children: [
                        pw.Text(title, style: s.heading),
                        pw.Text(
                          'Generated ${statement.generated}',
                          style: s.muted,
                        ),
                      ],
                    ),
                  ],
                ),
              ),
        footer: (context) => pw.Row(
          crossAxisAlignment: pw.CrossAxisAlignment.end,
          children: [
            pw.Expanded(
              child: pw.Text(
                'Made on this device from what you see in Settlo. Settlo is '
                'a record; it never holds or moves money.',
                style: s.muted,
              ),
            ),
            pw.SizedBox(width: 12),
            pw.Text(
              'Page ${context.pageNumber} of ${context.pagesCount}',
              style: s.muted,
            ),
          ],
        ),
        build: (_) => [
          for (final (i, block) in statement.blocks.indexed) ...[
            if (i > 0) pw.SizedBox(height: 18),
            ...switch (block) {
              StatementFacts(:final heading?) => [
                pw.Text(heading, style: s.heading),
                pw.SizedBox(height: 6),
                _facts(s, block.facts),
              ],
              StatementFacts() => [_facts(s, block.facts)],
              StatementTotal() => [_total(s, block)],
              StatementTable(rows: []) => [
                pw.Text(block.heading, style: s.heading),
                pw.SizedBox(height: 6),
                pw.Text(block.empty, style: s.muted),
              ],
              StatementTable() => [
                pw.Text(block.heading, style: s.heading),
                pw.SizedBox(height: 6),
                _table(s, block),
              ],
            },
          ],
        ],
      ),
    );
  return doc.save();
}

/// Label, value and an optional note, one per line.
pw.Widget _facts(_Styles s, List<StatementFact> facts) => pw.Column(
  children: [
    for (final (:label, :value, :note) in facts)
      pw.Padding(
        padding: const pw.EdgeInsets.symmetric(vertical: 3),
        child: pw.Row(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            pw.SizedBox(width: 96, child: pw.Text(label, style: s.muted)),
            pw.Expanded(
              child: pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.start,
                children: [
                  pw.Text('$value', style: s.body),
                  if (note != null) pw.Text(note, style: s.muted),
                ],
              ),
            ),
          ],
        ),
      ),
  ],
);

/// A total in the serif with its amount in words.
pw.Widget _total(_Styles s, StatementTotal total) => pw.Container(
  padding: const pw.EdgeInsets.all(14),
  decoration: pw.BoxDecoration(
    border: pw.Border.all(color: _hairline),
    borderRadius: pw.BorderRadius.circular(10),
  ),
  child: pw.Column(
    crossAxisAlignment: pw.CrossAxisAlignment.start,
    children: [
      pw.Text(total.label, style: s.muted),
      pw.SizedBox(height: 2),
      pw.Text(formatInr(total.amount), style: s.amount),
      pw.SizedBox(height: 2),
      pw.Text(total.words, style: s.body),
    ],
  ),
);

/// A table; a muted row is in the secondary colour.
pw.Widget _table(_Styles s, StatementTable table) {
  final last = table.header.length - 1;
  pw.Widget cell(Object text, int i, pw.TextStyle style) => pw.Padding(
    padding: const pw.EdgeInsets.symmetric(vertical: 5, horizontal: 4),
    child: pw.Text(
      '$text',
      style: style,
      textAlign: i == last ? pw.TextAlign.right : pw.TextAlign.left,
    ),
  );
  return pw.Table(
    border: const pw.TableBorder(
      horizontalInside: pw.BorderSide(color: _hairline, width: 0.5),
      bottom: pw.BorderSide(color: _hairline, width: 0.5),
    ),
    columnWidths: {last: const pw.IntrinsicColumnWidth()},
    children: [
      pw.TableRow(
        repeat: true,
        decoration: const pw.BoxDecoration(
          border: pw.Border(bottom: pw.BorderSide(color: _ink, width: 0.8)),
        ),
        children: [
          for (final (i, h) in table.header.indexed) cell(h, i, s.label),
        ],
      ),
      for (final r in table.rows)
        pw.TableRow(
          children: [
            for (final (i, c) in r.cells.indexed)
              cell(c, i, r.muted ? s.muted : s.body),
          ],
        ),
    ],
  );
}

/// `10 Nov 2026, 3:04 pm IST`: India's time at [instant], whatever the
/// device's zone.
String istStamp(DateTime instant) {
  final t = instant.toUtc().add(const Duration(hours: 5, minutes: 30));
  final hour = t.hour % 12 == 0 ? 12 : t.hour % 12;
  return '${_day(t)}, $hour:${t.minute.toString().padLeft(2, '0')} '
      '${t.hour < 12 ? 'am' : 'pm'} IST';
}

String _words(Paise p) {
  final w = amountInWords(p);
  return '${w[0].toUpperCase()}${w.substring(1)}';
}

String _named(String? name, String fallback) =>
    name == null || name.trim().isEmpty || isPhoneLike(name) ? fallback : name;

String _kind(SpaceKind kind) => switch (kind) {
  SpaceKind.flat => 'Flatmates',
  SpaceKind.trip => 'Trip',
  SpaceKind.friend => 'One friend',
  SpaceKind.other => 'Shared',
};

const _months = [
  'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', //
  'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
];

String _day(DateTime d) => '${d.day} ${_months[d.month - 1]} ${d.year}';

String _month(DateTime d) => '${_months[d.month - 1]} ${d.year}';

String _ordinal(int n) =>
    '$n${switch (n % 100) {
      11 || 12 || 13 => 'th',
      _ => switch (n % 10) {
        1 => 'st',
        2 => 'nd',
        3 => 'rd',
        _ => 'th',
      },
    }}';

// Printed on white: the light theme's ink and secondary text.
const _ink = PdfColor.fromInt(0xFF1B1B18);
const _secondary = PdfColor.fromInt(0xFF5F605B);
const _hairline = PdfColor.fromInt(0xFFD9D6CE);

final class _Styles {
  new(this.fonts);

  final StatementFonts fonts;

  late final pw.TextStyle body = pw.TextStyle(
    font: fonts.regular,
    fontSize: 10,
    color: _ink,
  );
  late final pw.TextStyle muted = body.copyWith(fontSize: 9, color: _secondary);
  late final pw.TextStyle label = body.copyWith(
    font: fonts.medium,
    fontSize: 9,
  );
  late final pw.TextStyle heading = body.copyWith(
    font: fonts.medium,
    fontSize: 13,
  );
  late final pw.TextStyle wordmark = pw.TextStyle(
    font: fonts.medium,
    fontSize: 22,
    letterSpacing: -0.6,
    color: _ink,
  );
  late final pw.TextStyle amount = pw.TextStyle(
    font: fonts.serif,
    fontSize: 24,
    color: _ink,
  );
}
