import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:settlo/shell.dart';
import 'package:settlo_activity/settlo_activity.dart';
import 'package:settlo_balances/settlo_balances.dart';
import 'package:settlo_core/settlo_core.dart';
import 'package:settlo_test_support/golden.dart';

import 'support/fake_activity.dart';
import 'support/fake_home.dart';

/// Home in the shell with [data] already loaded. Riverpod pauses widgets
/// under a disabled [TickerMode], as the golden harness sets, so the data
/// is loaded before the first frame rather than awaited after it.
Future<Widget> homeInShell(HomeData data) async {
  final container = ProviderContainer(
    overrides: [
      homeRepositoryProvider.overrideWithValue(FakeHomeRepository(data)),
      activityRepositoryProvider.overrideWithValue(FakeActivityRepository()),
    ],
  );
  addTearDown(container.dispose);
  await container.read(homeProvider.future);
  await container.read(activityFeedProvider.future);
  return UncontrolledProviderScope(
    container: container,
    child: SettloShell(
      currentIndex: 0,
      onTabSelected: (_) {},
      child: const HomeScreen(),
    ),
  );
}

/// Each Home state against its artboard: Main, HomeEmpty and HomeFound in
/// dark, and Main in light against HomeLight (the theme switch is not
/// built yet, so light is forced here).
void main() {
  final states = [
    ('main', homeMain, ['dark', 'light']),
    ('empty', homeEmpty, ['dark', 'light']),
    ('found', homeFound, ['dark']),
  ];
  for (final device in SettloGoldenDevices.all) {
    for (final (state, data, themes) in states) {
      for (final themeName in themes) {
        testWidgets('${device.name} $themeName home $state golden', (
          tester,
        ) async {
          await pumpSettloGolden(
            tester,
            device: device,
            theme: themeName == 'dark'
                ? SettloTheme.dark()
                : SettloTheme.light(),
            child: await homeInShell(data),
          );

          await expectLater(
            find.byKey(settloGoldenSurfaceKey),
            matchesGoldenFile(
              'goldens/home_${state}_${device.name}_$themeName.png',
            ),
          );
        });
      }
    }
  }

  testWidgets('owner mock beside empty Home at 390x844', (tester) async {
    await loadSettloFonts();
    final home = await homeInShell(homeEmpty);
    final mock = [
      File('../docs/design/home-mock.png'),
      File('docs/design/home-mock.png'),
    ].singleWhere((file) => file.existsSync());
    final mockBytes = mock.readAsBytesSync();
    final decoded = (await tester.runAsync(() async {
      final codec = await ui.instantiateImageCodec(
        mockBytes,
        targetWidth: 390,
        targetHeight: 844,
      );
      return (codec: codec, image: (await codec.getNextFrame()).image);
    }))!;
    final (:codec, :image) = decoded;
    final mockImage = image;
    addTearDown(() {
      mockImage.dispose();
      codec.dispose();
    });
    tester.view
      ..physicalSize = const Size(780, 844)
      ..devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    tester.platformDispatcher.accessibilityFeaturesTestValue =
        const FakeAccessibilityFeatures(disableAnimations: true);
    addTearDown(tester.platformDispatcher.clearAccessibilityFeaturesTestValue);

    await tester.pumpWidget(
      Directionality(
        textDirection: TextDirection.ltr,
        child: RepaintBoundary(
          key: settloGoldenSurfaceKey,
          child: SizedBox(
            width: 780,
            height: 844,
            child: Row(
              children: [
                SizedBox(
                  width: 390,
                  height: 844,
                  child: CustomPaint(painter: _MockPainter(mockImage)),
                ),
                SizedBox(
                  width: 390,
                  height: 844,
                  child: MaterialApp(theme: SettloTheme.dark(), home: home),
                ),
              ],
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await expectLater(
      find.byKey(settloGoldenSurfaceKey),
      matchesGoldenFile('goldens/home_comparison_390x844_dark.png'),
    );
  });
}

class _MockPainter extends CustomPainter {
  const new(this.image);

  final ui.Image image;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawImageRect(
      image,
      Rect.fromLTWH(0, 0, image.width.toDouble(), image.height.toDouble()),
      Offset.zero & size,
      Paint()..filterQuality = FilterQuality.high,
    );
  }

  @override
  bool shouldRepaint(_MockPainter oldDelegate) => oldDelegate.image != image;
}
