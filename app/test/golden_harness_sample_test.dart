import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/golden.dart';

void main() {
  for (final device in SettloGoldenDevices.all) {
    for (final theme in SettloGoldenTheme.values) {
      testWidgets('${device.name} ${theme.name} sample golden', (tester) async {
        var fontsLoaded = false;
        await pumpSettloGolden(
          tester,
          device: device,
          theme: theme,
          loadFonts: () async => fontsLoaded = true,
          child: SizedBox.expand(
            child: CustomPaint(
              painter: _SamplePainter(brightness: theme.brightness),
            ),
          ),
        );

        expect(fontsLoaded, isTrue);
        await expectLater(
          find.byKey(settloGoldenSurfaceKey),
          matchesGoldenFile(
            'goldens/golden_harness_${device.name}_${theme.name}.png',
          ),
        );
      });
    }
  }
}

class _SamplePainter extends CustomPainter {
  const new({required this.brightness});

  final Brightness brightness;

  @override
  void paint(Canvas canvas, Size size) {
    final isDark = brightness == Brightness.dark;
    final background = isDark
        ? const Color(0xFF0A0B0D)
        : const Color(0xFFF4F1EA);
    final surface = isDark ? const Color(0xFF1E2126) : const Color(0xFFFFFFFF);
    final action = isDark ? const Color(0xFFD8B36B) : const Color(0xFF1B1B18);

    canvas
      ..drawRect(Offset.zero & size, Paint()..color = background)
      ..drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromLTWH(20, 40, size.width - 40, 160),
          const Radius.circular(24),
        ),
        Paint()..color = surface,
      )
      ..drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromLTWH(20, size.height - 76, size.width - 40, 56),
          const Radius.circular(16),
        ),
        Paint()..color = action,
      );
  }

  @override
  bool shouldRepaint(covariant _SamplePainter oldDelegate) =>
      brightness != oldDelegate.brightness;
}
