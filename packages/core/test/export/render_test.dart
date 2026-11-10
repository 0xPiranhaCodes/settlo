import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:settlo_core/settlo_core.dart';

import 'fixtures.dart';

/// A 1x1 PNG.
final Uint8List _png = base64.decode(
  'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mNk'
  'YPhfDwAChwGA60e6kgAAAABJRU5ErkJggg==',
);

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

  test('a name that fails to draw prints "Name in another script"', () async {
    final images = await renderTextImages([
      'प्रिया',
    ], draw: (_) async => throw StateError('no font'));
    expect(images, isEmpty);

    const statement = Statement(
      title: 'Space summary',
      generated: '10 Nov 2026',
      blocks: [
        StatementFacts([(label: 'Members', value: 'प्रिया', note: null)]),
      ],
    );
    final failed = pdfWords(
      await statementPdf(statement, fonts: fonts, images: images),
    );
    expect(failed, contains('Members Name in another script'));

    final drawn = pdfWords(
      await statementPdf(
        statement,
        fonts: fonts,
        images: {
          'प्रिया': (png: _png, width: 30.0, height: 12.0, baseline: 9.0),
        },
      ),
    );
    expect(drawn, contains('Space summary'));
    expect(drawn, isNot(contains('another script')));
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
