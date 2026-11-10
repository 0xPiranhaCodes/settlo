import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:settlo_core/settlo_core.dart';

import 'fixtures.dart';

void main() {
  testWidgets('draws text as images, skipping what cannot be drawn', (
    tester,
  ) async {
    final images = (await tester.runAsync(
      () => renderTextImages(['प्रिया', '']),
    ))!;
    expect(images.keys, ['प्रिया']);
    final drawn = images['प्रिया']!;
    expect(drawn.width, greaterThan(0));
    expect(drawn.height, greaterThan(0));
    expect(drawn.png.sublist(1, 4), 'PNG'.codeUnits);
  });

  test('writes a statement PDF to a file off the UI isolate', () async {
    final dir = await Directory.systemTemp.createTemp('statement');
    addTearDown(() => dir.delete(recursive: true));
    final file = File('${dir.path}/s.pdf');
    await writeStatementPdf(
      loanStatement(arjunLoan(), generatedAt: DateTime.utc(2026, 11, 10)),
      file,
      fonts: fonts,
    );
    expect(pdfPages(await file.readAsBytes()), 1);
  });

  test('names each kind of space', () {
    String kind(SpaceKind k) {
      final f = flat();
      final summary = spaceSummary(
        SpaceSummary(id: f.id, name: f.name, kind: k, members: f.members),
        flatLedger(),
        generatedAt: DateTime.utc(2026, 11, 10),
      );
      return summary.blocks.whereType<StatementFacts>().first.facts.first.note!;
    }

    expect(
      [for (final k in SpaceKind.values) kind(k)],
      ['Flatmates', 'Trip', 'One friend', 'Shared'],
    );
  });
}
