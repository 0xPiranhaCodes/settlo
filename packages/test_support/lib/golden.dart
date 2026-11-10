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
    if (name != 'Figtree') continue;
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
  const new({required this.name, required this.size, this.textScale = 1});

  /// Accessibility text scale exercised by this viewport.
  final double textScale;

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

  /// Both phone viewports at standard and 200% accessibility text.
  static const accessible = <GoldenDevice>[
    canvas390,
    compact360,
    GoldenDevice(name: '390x844_text200', size: Size(390, 844), textScale: 2),
    GoldenDevice(name: '360x800_text200', size: Size(360, 800), textScale: 2),
  ];
}

/// Stable key for capturing only the configured device surface.
const settloGoldenSurfaceKey = ValueKey<String>('settlo-golden-surface');

/// Pumps [child] with deterministic viewport, theme, motion, and text settings.
///
/// [act] runs first, with tickers on, so the state it leaves (typed text,
/// a focus change, a button that became enabled) finishes animating; the
/// same tree is then pumped again with tickers off.
Future<void> pumpSettloGolden(
  WidgetTester tester, {
  required Widget child,
  required GoldenDevice device,
  required ThemeData theme,
  GoldenFontLoader loadFonts = loadSettloFonts,
  Future<void> Function(WidgetTester tester)? act,
}) async {
  await loadFonts();

  tester.view
    ..physicalSize = device.size
    ..devicePixelRatio = 1;
  tester.platformDispatcher
    ..textScaleFactorTestValue = device.textScale
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

  Widget surface({required bool tickers}) => MaterialApp(
    debugShowCheckedModeBanner: false,
    theme: theme,
    home: MediaQuery(
      data: MediaQueryData(
        size: device.size,
        textScaler: TextScaler.linear(device.textScale),
        disableAnimations: true,
      ),
      child: TickerMode(
        enabled: tickers,
        child: RepaintBoundary(key: settloGoldenSurfaceKey, child: child),
      ),
    ),
  );

  // Build once with tickers enabled so package images can enter Flutter's
  // image cache before the stable, ticker-free frame is captured.
  await tester.pumpWidget(surface(tickers: true));
  await act?.call(tester);
  await tester.pumpAndSettle();
  final context = tester.element(find.byKey(settloGoldenSurfaceKey));
  await tester.runAsync(() async {
    for (final image in tester.widgetList<Image>(find.byType(Image))) {
      await precacheImage(image.image, context);
    }
  });
  await tester.pumpWidget(surface(tickers: false));
  await tester.pump();
  expectSettloTapTargets(tester);
}

/// Walks each screen's widget tree and measures actual tap detector bounds.
/// Measures layout bounds rather than clipped semantics bounds: partially
/// scrolled rows must retain full targets when brought into view.
void expectSettloTapTargets(WidgetTester tester) {
  final failures = <String>[];
  for (final element in tester.allElements) {
    final widget = element.widget;
    final tappable = switch (widget) {
      GestureDetector(:final onTap, :final onTapUp, :final onTapDown) =>
        onTap != null || onTapUp != null || onTapDown != null,
      InkResponse(:final onTap) => onTap != null,
      _ => false,
    };
    if (!tappable) continue;
    // Flutter's platform text-selection handles are not app controls.
    var selectionHandle = false;
    element.visitAncestorElements((ancestor) {
      if (ancestor.widget.runtimeType.toString().contains('SelectionHandle')) {
        selectionHandle = true;
        return false;
      }
      return true;
    });
    if (selectionHandle) continue;
    final render = element.findRenderObject();
    if (render is! RenderBox || !render.hasSize) continue;
    final size = render.size;
    if (size.width < 44 || size.height < 44) {
      failures.add('${widget.runtimeType} ${widget.key}: $size');
    }
  }
  expect(failures, isEmpty, reason: 'Tap targets must be at least 44x44');
}
