import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// Loads any fonts needed by a golden before the widget is rendered.
///
/// App and package tests can provide their own bundled-asset loader without
/// coupling this shared harness to a particular package's assets.
typedef GoldenFontLoader = Future<void> Function();

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

/// Theme variants required for every Settlo golden.
enum SettloGoldenTheme {
  /// Dark-first product theme.
  dark(Brightness.dark),

  /// Light product theme.
  light(Brightness.light);

  new(this.brightness);

  /// Flutter brightness represented by this variant.
  final Brightness brightness;
}

/// Stable key for capturing only the configured device surface.
const settloGoldenSurfaceKey = ValueKey<String>('settlo-golden-surface');

/// Pumps [child] with deterministic viewport, theme, motion, and text settings.
Future<void> pumpSettloGolden(
  WidgetTester tester, {
  required Widget child,
  required GoldenDevice device,
  required SettloGoldenTheme theme,
  GoldenFontLoader? loadFonts,
}) async {
  await loadFonts?.call();

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
      theme: ThemeData(brightness: theme.brightness),
      home: MediaQuery(
        data: MediaQueryData(
          size: device.size,
          textScaler: TextScaler.noScaling,
          disableAnimations: true,
          accessibleNavigation: true,
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
