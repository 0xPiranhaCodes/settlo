import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:settlo_core/settlo_core.dart';

void main() {
  test('Home arc paints warm pixels above the bottom-right nav', () async {
    const size = Size(390, 844);
    final recorder = ui.PictureRecorder();
    const WelcomeBackgroundPainter(
      background: Color(0xFF0A0B0D),
      gold: Color(0xFFF2C77F),
      highlight: Color(0xFFF2C77F),
      placement: SettloArcPlacement.home,
    ).paint(Canvas(recorder), size);
    final image = await recorder.endRecording().toImage(
      size.width.toInt(),
      size.height.toInt(),
    );
    addTearDown(image.dispose);
    final bytes = await image.toByteData();
    expect(bytes, isNotNull);

    var warmPixels = 0;
    for (var y = 668; y < 752; y++) {
      for (var x = 150; x < 390; x++) {
        final offset = (y * size.width.toInt() + x) * 4;
        final red = bytes!.getUint8(offset);
        final blue = bytes.getUint8(offset + 2);
        if (red - blue > 30) warmPixels++;
      }
    }
    expect(warmPixels, greaterThan(0));
  });

  testWidgets('shared owner arcs paint and respond to token changes', (
    tester,
  ) async {
    const painter = WelcomeBackgroundPainter(
      background: Color(0xFF0A0B0D),
      gold: Color(0xFFD8B36A),
      highlight: Color(0xFFF2C77F),
    );
    await tester.pumpWidget(
      const RepaintBoundary(
        child: SizedBox(
          width: 390,
          height: 844,
          child: CustomPaint(painter: painter),
        ),
      ),
    );
    await tester.pump();

    expect(find.byType(CustomPaint), findsOneWidget);
    expect(painter.shouldRepaint(painter), isFalse);
    expect(
      painter.shouldRepaint(
        const WelcomeBackgroundPainter(
          background: Color(0xFFFFFFFF),
          gold: Color(0xFFD8B36A),
          highlight: Color(0xFFF2C77F),
        ),
      ),
      isTrue,
    );
    expect(
      painter.shouldRepaint(
        const WelcomeBackgroundPainter(
          background: Color(0xFF0A0B0D),
          gold: Color(0xFFD8B36A),
          highlight: Color(0xFFF2C77F),
          placement: SettloArcPlacement.home,
        ),
      ),
      isTrue,
    );
  });
}
