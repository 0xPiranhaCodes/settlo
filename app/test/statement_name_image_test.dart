import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:settlo_core/settlo_core.dart';
import 'package:settlo_test_support/golden.dart';

/// The test engine has no system fonts; these stand in for the phone's
/// own (test only, OFL 1.1, never app assets).
Future<void> _loadScriptFonts() async {
  for (final (family, file) in [
    ('Noto Sans Devanagari', 'NotoSansDevanagari-Regular.ttf'),
    ('Noto Naskh Arabic', 'NotoNaskhArabic-Regular.ttf'),
  ]) {
    final bytes = ByteData.sublistView(
      File('test/fonts/$file').readAsBytesSync(),
    );
    await (FontLoader(
      'packages/settlo_core/$family',
    )..addFont(Future.value(bytes))).load();
  }
}

/// [name] as the statement draws it, and that image decoded.
Future<(StatementImage, ui.Image)> _draw(
  WidgetTester tester,
  String name,
) async => (await tester.runAsync(() async {
  final drawn = (await renderTextImages([name]))[name]!;
  final codec = await ui.instantiateImageCodec(drawn.png);
  return (drawn, (await codec.getNextFrame()).image);
}))!;

void main() {
  setUp(() async {
    await loadSettloFonts();
    await _loadScriptFonts();
  });

  testWidgets('a Devanagari name is shaped by Flutter and embedded in the '
      'PDF as an image', (tester) async {
    const name = 'प्रिया शर्मा';
    const statement = Statement(
      title: 'Space summary',
      generated: '10 Nov 2026, 3:04 pm IST',
      blocks: [
        StatementFacts([(label: 'Members', value: name, note: null)]),
      ],
    );
    final pdf = (await tester.runAsync(() async {
      final fonts = await loadStatementFonts();
      expect(textsOutsideFonts(statement, fonts), {name});
      final images = await renderTextImages([name]);
      return latin1.decode(
        await statementPdf(statement, fonts: fonts, images: images),
      );
    }))!;
    expect(RegExp(r'/Subtype\s*/Image').hasMatch(pdf), isTrue);

    final (_, image) = await _draw(tester, name);
    await expectLater(
      image,
      matchesGoldenFile('goldens/statement_name_devanagari.png'),
    );
  });

  testWidgets('an Urdu name is drawn right to left', (tester) async {
    final (_, image) = await _draw(tester, 'عائشہ خان');
    await expectLater(
      image,
      matchesGoldenFile('goldens/statement_name_urdu.png'),
    );
  });

  testWidgets('every script gets an image with a 10pt size and baseline', (
    tester,
  ) async {
    for (final name in [
      'தமிழ்செல்வி', // Tamil
      'সুমিতা', // Bengali
      'Riya 🎉', // emoji
      'Priya प्रिया', // Latin and Devanagari
      'प्रिया शर्मा',
      'عائشہ خان',
    ]) {
      final (drawn, image) = await _draw(tester, name);
      expect(drawn.png, isNotEmpty, reason: name);
      expect(image.width, (drawn.width * 4).ceil(), reason: name);
      expect(drawn.width, inInclusiveRange(10, 120), reason: name);
      expect(drawn.height, inInclusiveRange(10, 30), reason: name);
      // The alphabetic baseline sits in the lower part of the line.
      expect(
        drawn.baseline,
        inInclusiveRange(drawn.height * 0.5, drawn.height),
        reason: name,
      );
    }
  });
}
