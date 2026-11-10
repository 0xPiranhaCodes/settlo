import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:settlo_core/settlo_core.dart';
import 'package:settlo_test_support/golden.dart';

const _name = 'प्रिया शर्मा';

void main() {
  testWidgets('a Devanagari name is shaped by Flutter and embedded in the '
      'PDF as an image', (tester) async {
    await loadSettloFonts();
    // The test engine has no system fonts; this one stands in for the
    // phone's Devanagari font (test only, OFL 1.1).
    await (FontLoader('packages/settlo_core/Noto Sans Devanagari')..addFont(
          Future.value(
            ByteData.sublistView(
              File('test/fonts/NotoSansDevanagari-Regular.ttf')
                  .readAsBytesSync(),
            ),
          ),
        ))
        .load();
    final (:image, :pdf) = (await tester.runAsync(() async {
      final fonts = await loadStatementFonts();
      const statement = Statement(
        title: 'Space summary',
        generated: '10 Nov 2026, 3:04 pm IST',
        blocks: [
          StatementFacts([(label: 'Members', value: _name, note: null)]),
        ],
      );
      expect(textsOutsideFonts(statement, fonts), {_name});
      final images = await renderTextImages(
        textsOutsideFonts(statement, fonts),
      );
      final drawn = images[_name]!;
      expect(drawn.width, greaterThan(0));
      expect(drawn.height, greaterThan(0));
      final codec = await ui.instantiateImageCodec(drawn.png);
      return (
        image: (await codec.getNextFrame()).image,
        pdf: latin1.decode(
          await statementPdf(statement, fonts: fonts, images: images),
        ),
      );
    }))!;

    expect(RegExp(r'/Subtype\s*/Image').hasMatch(pdf), isTrue);
    await expectLater(
      image,
      matchesGoldenFile('goldens/statement_name_devanagari.png'),
    );
  });
}
