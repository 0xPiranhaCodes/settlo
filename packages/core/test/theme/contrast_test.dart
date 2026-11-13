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

      test('control outlines clear 3:1 on inputs and cards', () {
        for (final background in [
          colors.background,
          colors.surface,
          colors.surfaceRaised,
        ]) {
          expect(
            contrast(colors.buttonBorder, background),
            greaterThanOrEqualTo(3),
          );
        }
      });

      test('surfaceHighest carries primary text only', () {
        final onHighest = colors.textPairs.where(
          (p) => p.background == colors.surfaceHighest,
        );
        expect(onHighest.map((p) => p.text), [colors.textPrimary]);
      });

      test('covers every text token on every content surface', () {
        // 11 text colours x 3 surfaces, plus 7 special pairs. Welcome uses
        // the lightest gradient stop so the whole action is covered.
        expect(colors.textPairs, hasLength(40));
      });
    });
  }

  test('dark tokens never have a green cast', () {
    const c = SettloColors.dark;
    // Supplied check/logo artwork is the sole brand-art exception. It is
    // rendered untinted, not a theme token; never allowlist a UI fill for it.
    final fills = {
      'background': c.background,
      'surface': c.surface,
      'surfaceRaised': c.surfaceRaised,
      'surfaceHighest': c.surfaceHighest,
      'hairline': c.hairline,
      'buttonBorder': c.buttonBorder,
      'specular': c.specular,
      'glass': c.glass,
      'glassFallback': c.glassFallback,
      'glassBorder': c.glassBorder,
      'action': c.action,
      'onAction': c.onAction,
      'onNavActive': c.onNavActive,
      'welcomeAction': c.welcomeAction,
      'brandAccent': c.brandAccent,
      'welcomeActionTop': c.welcomeActionTop,
      'welcomeActionBottom': c.welcomeActionBottom,
      'welcomeActionHighlight': c.welcomeActionHighlight,
      'welcomeActionShadow': c.welcomeActionShadow,
      'navActiveStart': c.navActiveStart,
      'navActiveEnd': c.navActiveEnd,
      'textPrimary': c.textPrimary,
      'textSecondary': c.textSecondary,
      'textMuted': c.textMuted,
      'pending': c.pending,
      'error': c.error,
      for (final tone in MoneyTone.values) 'money.${tone.name}': c.money(tone),
    };
    // Two 8-bit channel steps allow rounding, not a visible green tint.
    for (final entry in fills.entries) {
      expect(
        entry.value.g - math.max(entry.value.r, entry.value.b),
        lessThanOrEqualTo(2 / 255),
        reason: entry.key,
      );
    }
  });

  test('dark surface levels visibly separate without losing AA labels', () {
    const c = SettloColors.dark;
    final surfaces = [
      c.background,
      c.surface,
      c.surfaceRaised,
      c.surfaceHighest,
    ];
    for (var i = 1; i < surfaces.length; i++) {
      expect(
        surfaces[i].computeLuminance(),
        greaterThan(surfaces[i - 1].computeLuminance()),
      );
      expect(contrast(surfaces[i], surfaces[i - 1]), greaterThanOrEqualTo(1.2));
    }
    for (final text in [c.textSecondary, c.textMuted]) {
      expect(text.r, text.g);
      expect(text.g, text.b);
      for (final surface in surfaces) {
        expect(contrast(text, surface), greaterThanOrEqualTo(4.5));
      }
    }
    expect(c.background, const Color(0xFF000000));
    expect(c.glass.a, closeTo(0x9E / 255, 0.0001));
    expect(c.glassFallback.a, closeTo(0xEB / 255, 0.0001));
  });

  test('dark money and pending roles follow the owner scope', () {
    const c = SettloColors.dark;
    expect(c.money(MoneyTone.owedToYou), c.action);
    expect(c.action, const Color(0xFFFEBD11));
    expect(c.pending, c.textSecondary);
    expect(c.money(MoneyTone.youOwe), const Color(0xFFF2AB98));
    expect(c.error, const Color(0xFFFF9CA3));
    expect({
      c.money(MoneyTone.owedToYou),
      c.money(MoneyTone.youOwe),
      c.pending,
    }, hasLength(3));
    for (final surface in [
      c.background,
      c.surface,
      c.surfaceRaised,
      c.surfaceHighest,
    ]) {
      expect(contrast(c.action, surface), greaterThanOrEqualTo(4.5));
    }
    // Neutral ink stays AA on the marigold action backing.
    for (final label in [c.onAction, c.onNavActive]) {
      expect(label, const Color(0xFF111111));
      expect(contrast(label, c.action), greaterThanOrEqualTo(4.5));
    }
  });

  test('light Home jade clears text and icon contrast', () {
    const c = SettloColors.light;
    for (final surface in [c.background, c.surface, c.surfaceRaised]) {
      final ratio = contrast(c.brandAccent, surface);
      expect(ratio, greaterThanOrEqualTo(4.5), reason: '$surface');
      expect(ratio, greaterThanOrEqualTo(3), reason: 'icon on $surface');
    }
  });
}
