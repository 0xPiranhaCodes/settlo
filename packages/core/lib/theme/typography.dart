import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

const _tabular = [FontFeature.tabularFigures()];

/// Type scale from the canvas. Figtree for all text (body 400, labels and
/// buttons 500), IBM Plex Serif 500 for amounts at 20px and above, tabular
/// figures everywhere.
abstract final class SettloTypography {
  /// Amounts at this size and above are set in the serif.
  static const double serifFrom = 20;

  /// Figtree at [size] and [weight] (400 or 500), tabular figures.
  static TextStyle figtree(
    double size, {
    FontWeight weight = FontWeight.w400,
    double? letterSpacing,
    Color? color,
  }) => GoogleFonts.figtree(
    fontSize: size,
    fontWeight: weight,
    letterSpacing: letterSpacing,
    color: color,
    fontFeatures: _tabular,
  );

  /// The style for an amount at [size]: IBM Plex Serif 500 from
  /// [serifFrom], otherwise Figtree 500.
  static TextStyle amount(double size, {Color? color}) {
    if (size < serifFrom) {
      return figtree(size, weight: FontWeight.w500, color: color);
    }
    return GoogleFonts.ibmPlexSerif(
      fontSize: size,
      fontWeight: FontWeight.w500,
      letterSpacing: size >= 32 ? -1 : -0.8,
      height: 1.05,
      color: color,
      fontFeatures: _tabular,
    );
  }

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
