import 'package:flutter_test/flutter_test.dart';

export 'package:settlo_test_support/golden.dart' show loadSettloFonts;

/// Compares a core golden against its canonical Linux-generated image.
Future<void> expectGolden(Finder finder, String name) async {
  await expectLater(finder, matchesGoldenFile('goldens/$name.png'));
}
