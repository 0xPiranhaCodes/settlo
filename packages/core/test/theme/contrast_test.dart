import 'dart:math' as math;

import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:settlo_core/settlo_core.dart';

/// WCAG 2.x contrast ratio of two opaque colours.
double contrast(Color a, Color b) {
  double channel(double c) =>
      c <= 0.04045 ? c / 12.92 : math.pow((c + 0.055) / 1.055, 2.4).toDouble();
  double luminance(Color c) =>
      0.2126 * channel(c.r) + 0.7152 * channel(c.g) + 0.0722 * channel(c.b);
  final la = luminance(a);
  final lb = luminance(b);
  return (math.max(la, lb) + 0.05) / (math.min(la, lb) + 0.05);
}

void main() {
  test('contrast() matches known WCAG values', () {
    const black = Color(0xFF000000);
    const white = Color(0xFFFFFFFF);
    expect(contrast(black, white), closeTo(21, 0.01));
    expect(contrast(white, white), 1);
    expect(contrast(const Color(0xFF777777), white), closeTo(4.48, 0.01));
  });

  // Every pair is body text, so 4.5:1 applies throughout; no pair relies on
  // the 3:1 large-text allowance.
  for (final (name, colors) in [
    ('dark', SettloColors.dark),
    ('light', SettloColors.light),
  ]) {
    group('$name text/background pairs', () {
      for (final pair in colors.textPairs) {
        test('${pair.name} >= 4.5:1', () {
          expect(pair.background.a, 1, reason: 'background must be opaque');
          expect(
            contrast(pair.text, pair.background),
            greaterThanOrEqualTo(4.5),
          );
        });
      }

      test('surfaceHighest carries primary text only', () {
        final onHighest = colors.textPairs.where(
          (p) => p.background == colors.surfaceHighest,
        );
        expect(onHighest.map((p) => p.text), [colors.textPrimary]);
      });

      test('covers every text token on every content surface', () {
        // 8 text colours x 3 surfaces, plus 4 special pairs.
        expect(colors.textPairs, hasLength(28));
      });
    });
  }
}
