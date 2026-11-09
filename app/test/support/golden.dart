import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

/// Loads fonts before a golden is pumped; defaults to [loadSettloFonts].
typedef GoldenFontLoader = Future<void> Function();

var _settloFontsAreLoaded = false;

/// Loads the bundled Settlo fonts under their direct and package family names.
Future<void> loadSettloFonts() async {
  if (_settloFontsAreLoaded) return;
  await _loadSettloFonts();
  _settloFontsAreLoaded = true;
}

Future<void> _loadSettloFonts() async {
  TestWidgetsFlutterBinding.ensureInitialized();
  final manifest = jsonDecode(
    await rootBundle.loadString('FontManifest.json'),
  ) as List<dynamic>;
  for (final family in manifest.cast<Map<String, dynamic>>()) {
    final name = (family['family'] as String).split('/').last;
    if (name != 'Figtree' && name != 'IBM Plex Serif') continue;
    final files = [
      for (final font in (family['fonts'] as List).cast<Map<String, dynamic>>())
        rootBundle.load(font['asset'] as String),
    ];
    for (final loaderName in [name, 'packages/settlo_core/$name']) {
      final loader = FontLoader(loaderName);
      files.forEach(loader.addFont);
      await loader.load();
    }
  }
}

/// A stable logical viewport used by Settlo golden tests.
@immutable
final class GoldenDevice {
  /// Creates a named golden viewport.
  const new({required this.name, required this.size});

  /// File-name-safe device identifier.
  final String name;

  /// Logical pixel size at a fixed device pixel ratio of 1.
  final Size size;
}

/// The two viewport sizes required for every Settlo screen.
abstract final class SettloGoldenDevices {
  /// Primary canvas size.
  static const canvas390 = GoldenDevice(name: '390x844', size: Size(390, 844));

  /// Compact reflow size.
  static const compact360 = GoldenDevice(name: '360x800', size: Size(360, 800));

  /// All supported golden devices.
  static const all = <GoldenDevice>[canvas390, compact360];
}

/// Stable key for capturing only the configured device surface.
const settloGoldenSurfaceKey = ValueKey<String>('settlo-golden-surface');

/// Pumps [child] with deterministic viewport, theme, motion, and text settings.
Future<void> pumpSettloGolden(
  WidgetTester tester, {
  required Widget child,
  required GoldenDevice device,
  required ThemeData theme,
  GoldenFontLoader loadFonts = loadSettloFonts,
}) async {
  await loadFonts();

  tester.view
    ..physicalSize = device.size
    ..devicePixelRatio = 1;
  tester.platformDispatcher
    ..textScaleFactorTestValue = 1
    ..accessibilityFeaturesTestValue = const FakeAccessibilityFeatures(
      disableAnimations: true,
    );

  addTearDown(() {
    tester.view
      ..resetPhysicalSize()
      ..resetDevicePixelRatio();
    tester.platformDispatcher
      ..clearTextScaleFactorTestValue()
      ..clearAccessibilityFeaturesTestValue();
  });

  await tester.pumpWidget(
    MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: theme,
      home: MediaQuery(
        data: MediaQueryData(
          size: device.size,
          textScaler: TextScaler.noScaling,
          disableAnimations: true,
        ),
        child: TickerMode(
          enabled: false,
          child: RepaintBoundary(key: settloGoldenSurfaceKey, child: child),
        ),
      ),
    ),
  );
  await tester.pump();
}
