import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:settlo_core/settlo_core.dart';

void main() {
  for (final reduceMotion in [false, true]) {
    testWidgets('press response respects Reduce Motion $reduceMotion', (
      tester,
    ) async {
      var taps = 0;
      await tester.pumpWidget(
        MaterialApp(
          theme: SettloTheme.dark(),
          home: MediaQuery(
            data: MediaQueryData(disableAnimations: reduceMotion),
            child: Center(
              child: SPressable(
                onTap: () => taps++,
                child: const SizedBox(width: 16, height: 16),
              ),
            ),
          ),
        ),
      );
      expect(tester.getSize(find.byType(SPressable)), const Size(44, 44));
      final gesture = await tester.startGesture(
        tester.getCenter(find.byType(SPressable)),
      );
      await tester.pump(SettloMotion.press);
      expect(
        tester.widget<AnimatedScale>(find.byType(AnimatedScale)).scale,
        reduceMotion ? 1 : SettloMotion.pressedScale,
      );
      expect(taps, 0);
      await gesture.up();
      await tester.pumpAndSettle();
      expect(taps, 1);
      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      expect(taps, 2);
    });
  }

  testWidgets('disabled pressable cannot activate', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: SettloTheme.dark(),
        home: const Center(child: SPressable(onTap: null, child: Text('Busy'))),
      ),
    );
    await tester.tap(find.text('Busy'));
    await tester.pumpAndSettle();
    expect(tester.widget<AnimatedScale>(find.byType(AnimatedScale)).scale, 1);
  });
}
