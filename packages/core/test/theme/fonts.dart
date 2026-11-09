import 'dart:io';

import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:settlo_core/settlo_core.dart';

/// Loads the bundled Figtree and IBM Plex Serif through google_fonts, with
/// runtime fetching off so a missing asset fails the test instead of going
/// to the network.
Future<void> loadSettloFonts() async {
  TestWidgetsFlutterBinding.ensureInitialized();
  GoogleFonts.config.allowRuntimeFetching = false;
  SettloTypography.textTheme(const Color(0xFF000000));
  SettloTypography.amount(46);
  await GoogleFonts.pendingFonts();
}

/// Goldens are rendered on macOS; other hosts rasterise text differently,
/// so they still build and lay out the widget (and count for coverage) but
/// skip the pixel comparison.
Future<void> expectGolden(Finder finder, String name) async {
  if (!Platform.isMacOS) return;
  await expectLater(finder, matchesGoldenFile('goldens/$name.png'));
}
