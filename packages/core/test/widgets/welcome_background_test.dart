import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:settlo_core/settlo_core.dart';

void main() {
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
  });
}
