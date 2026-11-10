import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:settlo_core/settlo_core.dart';

import 'fixtures.dart';

/// 5,000 expenses, one every day or so for about 14 years, split three
/// ways.
SpaceLedger _large() => SpaceLedger(
  today: DateTime(2026, 11, 10),
  expenses: [
    for (var i = 4999; i >= 0; i--)
      SpaceExpense(
        id: 'e$i',
        description: 'Groceries $i',
        amount: Paise(10000 + i),
        spentOn: DateTime(2013, 1, 1 + i),
        payers: [(memberId: 'm1', amount: Paise(10000 + i))],
        splits: [
          for (final e in splitEqual(Paise(10000 + i), [
            'm1',
            'm2',
            'm3',
          ], payer: 'm1').entries)
            (memberId: e.key, amount: e.value, percentBp: null, shares: null),
        ],
      ),
  ],
);

void main() {
  test('5,000 expenses: built off the UI isolate, across pages', () async {
    final space = flat();
    final ledger = _large();
    final dir = await Directory.systemTemp.createTemp('export');
    addTearDown(() => dir.delete(recursive: true));
    final csv = File('${dir.path}/out.csv');
    final pdf = File('${dir.path}/out.pdf');

    // Ticks every 5 ms on this (the UI) isolate; a long gap means it was
    // blocked.
    final clock = Stopwatch()..start();
    var last = Duration.zero;
    var longest = Duration.zero;
    var ticks = 0;
    final timer = Timer.periodic(const Duration(milliseconds: 5), (_) {
      final now = clock.elapsed;
      if (now - last > longest) longest = now - last;
      last = now;
      ticks++;
    });
    final summary = spaceSummary(space, ledger, generatedAt: DateTime.now());
    await writeSpaceExport(
      space,
      ledger,
      summary,
      csv: csv,
      pdf: pdf,
      fonts: fonts,
    );
    timer.cancel();

    expect(ticks, greaterThan(5), reason: 'the export took real time');
    expect(longest, lessThan(const Duration(milliseconds: 250)));

    final lines = await csv.readAsLines();
    expect(lines, hasLength(1 + 5000 * 3));
    expect(lines.last, startsWith('5000,2026-09-09,Groceries 4999,'));
    expect(await csv.readAsBytes(), utf8.encode(spaceCsv(space, ledger)));

    // One row a month for about 14 years breaks across pages.
    final months = summary.blocks.whereType<StatementTable>().last;
    expect(months.heading, 'By month');
    expect(months.rows, hasLength(165));
    expect(pdfPages(await pdf.readAsBytes()), greaterThan(2));
  });
}
