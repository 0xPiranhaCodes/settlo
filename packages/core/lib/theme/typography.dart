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

  /// largeTitle: 34pt, 600 weight in the platform Dynamic Type ramp.
  static TextStyle largeTitle({
    Color? color,
    double? letterSpacing,
    FontWeight weight = FontWeight.w600,
  }) => figtree(34, weight: weight, color: color, letterSpacing: letterSpacing);

  /// title1: 28pt, 600 weight in the platform Dynamic Type ramp.
  static TextStyle title1({
    Color? color,
    double? letterSpacing,
    FontWeight weight = FontWeight.w600,
  }) => figtree(28, weight: weight, color: color, letterSpacing: letterSpacing);

  /// title2: 22pt, 600 weight in the platform Dynamic Type ramp.
  static TextStyle title2({
    Color? color,
    double? letterSpacing,
    FontWeight weight = FontWeight.w600,
  }) => figtree(22, weight: weight, color: color, letterSpacing: letterSpacing);

  /// title3: 20pt, 600 weight in the platform Dynamic Type ramp.
  static TextStyle title3({
    Color? color,
    double? letterSpacing,
    FontWeight weight = FontWeight.w600,
  }) => figtree(20, weight: weight, color: color, letterSpacing: letterSpacing);

  /// headline: 17pt, 600 weight in the platform Dynamic Type ramp.
  static TextStyle headline({
    Color? color,
    double? letterSpacing,
    FontWeight weight = FontWeight.w600,
  }) => figtree(17, weight: weight, color: color, letterSpacing: letterSpacing);

  /// body: 17pt, 400 weight in the platform Dynamic Type ramp.
  static TextStyle body({
    Color? color,
    double? letterSpacing,
    FontWeight weight = FontWeight.w400,
  }) => figtree(17, weight: weight, color: color, letterSpacing: letterSpacing);

  /// callout: 16pt, 400 weight in the platform Dynamic Type ramp.
  static TextStyle callout({
    Color? color,
    double? letterSpacing,
    FontWeight weight = FontWeight.w400,
  }) => figtree(16, weight: weight, color: color, letterSpacing: letterSpacing);

  /// subheadline: 15pt, 400 weight in the platform Dynamic Type ramp.
  static TextStyle subheadline({
    Color? color,
    double? letterSpacing,
    FontWeight weight = FontWeight.w400,
  }) => figtree(15, weight: weight, color: color, letterSpacing: letterSpacing);

  /// footnote: 13pt, 400 weight in the platform Dynamic Type ramp.
  static TextStyle footnote({
    Color? color,
    double? letterSpacing,
    FontWeight weight = FontWeight.w400,
  }) => figtree(13, weight: weight, color: color, letterSpacing: letterSpacing);

  /// caption1: 12pt, 400 weight in the platform Dynamic Type ramp.
  static TextStyle caption1({
    Color? color,
    double? letterSpacing,
    FontWeight weight = FontWeight.w400,
  }) => figtree(12, weight: weight, color: color, letterSpacing: letterSpacing);

  /// caption2: 11pt, 500 weight in the platform Dynamic Type ramp.
  static TextStyle caption2({
    Color? color,
    double? letterSpacing,
    FontWeight weight = FontWeight.w500,
  }) => figtree(11, weight: weight, color: color, letterSpacing: letterSpacing);

  /// Material roles backed by the same platform ramp.
  static TextTheme textTheme(Color color) => TextTheme(
    displayLarge: largeTitle(),
    displayMedium: title1(),
    displaySmall: title2(),
    headlineLarge: largeTitle(),
    headlineMedium: title1(),
    headlineSmall: title2(),
    titleLarge: title3(),
    titleMedium: headline(),
    titleSmall: subheadline(),
    bodyLarge: body(),
    bodyMedium: body(),
    bodySmall: subheadline(),
    labelLarge: callout(weight: FontWeight.w600),
    labelMedium: footnote(letterSpacing: 0.3),
    labelSmall: caption2(),
  ).apply(bodyColor: color, displayColor: color);
}
