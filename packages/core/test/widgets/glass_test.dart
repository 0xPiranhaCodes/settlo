import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:settlo_core/settlo_core.dart';

void main() {
  test(
    'isolated slow frames do not disable blur; sustained raster cost does',
    () {
      final budget = GlassFrameBudget()
        ..record(const Duration(milliseconds: 40));
      for (var i = 0; i < 29; i++) {
        budget.record(const Duration(milliseconds: 4));
      }
      expect(budget.exceeded, isFalse);
      for (var i = 0; i < 12; i++) {
        budget.record(const Duration(milliseconds: 24));
      }
      expect(budget.exceeded, isTrue);
      budget.record(Duration.zero);
      expect(budget.exceeded, isTrue);
    },
  );

  test('glass and bronze labels retain 4.5 contrast '
      'over extreme and image backdrops', () async {
    double contrast(Color a, Color b) {
      final x = a.computeLuminance();
      final y = b.computeLuminance();
      return (x > y ? x + 0.05 : y + 0.05) / (x > y ? y + 0.05 : x + 0.05);
    }

    final busy = await _busyBackdrop();
    for (final c in [SettloColors.dark, SettloColors.light]) {
      for (final backdrop in [Colors.black, Colors.white, ...busy]) {
        final tint = Color.alphaBlend(
          c.glass.withValues(alpha: SettloElevation.glassTint),
          backdrop,
        );
        final glow = Color.alphaBlend(
          c.specular.withValues(alpha: 0.02),
          Color.alphaBlend(
            c.surface.withValues(alpha: SettloElevation.glassLegibility),
            tint,
          ),
        );
        expect(contrast(c.textPrimary, glow), greaterThanOrEqualTo(4.5));
      }
      for (final bronze in [c.navActiveStart, c.navActiveEnd]) {
        final glow = Color.alphaBlend(
          c.specular.withValues(alpha: 0.02),
          bronze,
        );
        expect(contrast(c.onNavActive, glow), greaterThanOrEqualTo(4.5));
      }
      expect(contrast(c.textPrimary, c.surface), greaterThanOrEqualTo(4.5));
    }
  });

  testWidgets('high contrast removes blur and Reduce Motion removes sliding', (
    tester,
  ) async {
    Future<void> pump({required bool accessible, required int selected}) =>
        tester.pumpWidget(
          MaterialApp(
            theme: SettloTheme.dark(),
            home: MediaQuery(
              data: MediaQueryData(
                highContrast: accessible,
                disableAnimations: accessible,
              ),
              child: Center(
                child: SizedBox(
                  width: 320,
                  child: SGlassTabBar(
                    tabs: const [
                      (icon: Icon(Icons.home), label: 'Home'),
                      (icon: Icon(Icons.receipt), label: 'Activity'),
                    ],
                    currentIndex: selected,
                    onTap: (_) {},
                  ),
                ),
              ),
            ),
          ),
        );
    await pump(accessible: false, selected: 0);
    expect(find.byType(BackdropFilter), findsOneWidget);
    await pump(accessible: false, selected: 1);
    final moving = tester.widget<AnimatedPositionedDirectional>(
      find.byKey(const ValueKey('nav-active-pill')),
    );
    expect(moving.duration, SettloMotion.selection);
    expect(moving.start, greaterThan(0));
    await pump(accessible: true, selected: 0);
    expect(find.byType(BackdropFilter), findsNothing);
    expect(
      tester
          .widget<AnimatedPositionedDirectional>(
            find.byKey(const ValueKey('nav-active-pill')),
          )
          .duration,
      Duration.zero,
    );
  });
}

// Sample the real Home image, including money, type and the bronze curve.
Future<List<Color>> _busyBackdrop() async {
  final bytes = await File('../../app/test/goldens/home_main_390x844_dark.png')
      .readAsBytes();
  final codec = await ui.instantiateImageCodec(bytes, targetWidth: 120);
  final frame = await codec.getNextFrame();
  final data = (await frame.image.toByteData())!;
  final colors = <Color>[];
  for (var i = 0; i < data.lengthInBytes; i += 16) {
    colors.add(
      Color.fromARGB(
        data.getUint8(i + 3),
        data.getUint8(i),
        data.getUint8(i + 1),
        data.getUint8(i + 2),
      ),
    );
  }
  frame.image.dispose();
  codec.dispose();
  return colors;
}
