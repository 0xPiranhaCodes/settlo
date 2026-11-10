import 'package:flutter/material.dart';

const _package = 'settlo_core';
const _tabular = [FontFeature.tabularFigures()];

/// Type scale from the canvas. Figtree for all text, including amounts, with
/// tabular figures everywhere.
abstract final class SettloTypography {
  /// Bundled text family; pair with `package: 'settlo_core'`.
  static const String figtreeFamily = 'Figtree';

  /// Figtree at [size] and [weight] (400, 500 or 600), tabular figures.
  static TextStyle figtree(
    double size, {
    FontWeight weight = FontWeight.w400,
    double? letterSpacing,
    Color? color,
  }) => TextStyle(
    fontFamily: figtreeFamily,
    package: _package,
    fontSize: size,
    fontWeight: weight,
    letterSpacing: letterSpacing,
    color: color,
    fontFeatures: _tabular,
  );

  /// Figtree 500 for an amount at [size].
  static TextStyle amount(double size, {Color? color}) => figtree(
    size,
    weight: FontWeight.w500,
    letterSpacing: size >= 32 ? -1 : -0.8,
    color: color,
  ).copyWith(height: 1.05);

  /// Material text theme in [color].
  ///
  /// headlineSmall 22/500 (screen titles, wordmark), titleMedium 17/500,
  /// titleSmall and labelLarge 15/500 (row titles, buttons), bodyLarge
  /// 15/400, bodyMedium 13/400 (captions), bodySmall and labelMedium 12/400
  /// (section labels), labelSmall 11/400 (tab bar).
  static TextTheme textTheme(Color color) => TextTheme(
    headlineSmall: figtree(22, weight: FontWeight.w500, letterSpacing: -0.6),
    titleMedium: figtree(17, weight: FontWeight.w500),
    titleSmall: figtree(15, weight: FontWeight.w500),
    bodyLarge: figtree(15),
    bodyMedium: figtree(13),
    bodySmall: figtree(12),
    labelLarge: figtree(15, weight: FontWeight.w500),
    labelMedium: figtree(12, letterSpacing: 0.3),
    labelSmall: figtree(11),
  ).apply(bodyColor: color, displayColor: color);
}
