import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

/// Loads every font in the bundle's FontManifest (Figtree and IBM Plex
/// Serif), under both its own family name and the `packages/settlo_core/`
/// name that `package: 'settlo_core'` styles resolve to.
// TODO(Inj3ct0R): move into the shared golden support (#31).
Future<void> loadSettloFonts() async {
  TestWidgetsFlutterBinding.ensureInitialized();
  final manifest = jsonDecode(
    await rootBundle.loadString('FontManifest.json'),
  ) as List<dynamic>;
  for (final family in manifest.cast<Map<String, dynamic>>()) {
    final name = (family['family'] as String).split('/').last;
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

/// Goldens are rendered on macOS; other hosts rasterise text differently,
/// so they still build and lay out the widget (and count for coverage) but
/// skip the pixel comparison.
Future<void> expectGolden(Finder finder, String name) async {
  // TODO(Inj3ct0R): compare on the pinned Linux image via the shared
  // harness (#31) and drop this macOS-only early return.
  if (!Platform.isMacOS) return;
  await expectLater(finder, matchesGoldenFile('goldens/$name.png'));
}
