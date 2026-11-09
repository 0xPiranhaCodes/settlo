import 'package:flutter/material.dart';
import 'package:settlo_core/theme/colors.dart';
import 'package:settlo_core/theme/tokens.dart';
import 'package:settlo_core/theme/typography.dart';

/// Settlo [ThemeData]. Dark is the default.
abstract final class SettloTheme {
  /// Dark theme: gold primary action.
  static ThemeData dark() => _build(SettloColors.dark, Brightness.dark);

  /// Light theme: ink primary action.
  static ThemeData light() => _build(SettloColors.light, Brightness.light);

  static ThemeData _build(SettloColors c, Brightness brightness) {
    final text = SettloTypography.textTheme(c.textPrimary);
    // Mint and coral stay out of the scheme (they are reachable only through
    // MoneyTone), so errors are neutral rather than red.
    final scheme = ColorScheme(
      brightness: brightness,
      primary: c.action,
      onPrimary: c.onAction,
      secondary: c.surfaceHighest,
      onSecondary: c.textPrimary,
      error: c.textPrimary,
      onError: c.background,
      surface: c.background,
      onSurface: c.textPrimary,
      onSurfaceVariant: c.textSecondary,
      surfaceContainerLow: c.surface,
      surfaceContainer: c.surfaceRaised,
      surfaceContainerHigh: c.surfaceHighest,
      outline: c.buttonBorder,
      outlineVariant: c.hairline,
    );
    const buttonShape = RoundedRectangleBorder(
      borderRadius: BorderRadius.all(Radius.circular(SettloRadius.button)),
    );
    const buttonSize = Size(SettloSpacing.minTouchTarget, 50);
    return ThemeData(
      brightness: brightness,
      colorScheme: scheme,
      scaffoldBackgroundColor: c.background,
      textTheme: text,
      extensions: [c],
      splashFactory: NoSplash.splashFactory,
      materialTapTargetSize: MaterialTapTargetSize.padded,
      dividerTheme: DividerThemeData(
        color: c.hairline,
        thickness: SettloElevation.hairline,
        space: SettloElevation.hairline,
      ),
      cardTheme: CardThemeData(
        color: c.surface,
        elevation: 0,
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(
          borderRadius: const BorderRadius.all(
            Radius.circular(SettloRadius.card),
          ),
          side: BorderSide(color: c.hairline),
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: c.action,
          foregroundColor: c.onAction,
          minimumSize: buttonSize,
          shape: buttonShape,
          textStyle: text.labelLarge,
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          backgroundColor: c.surfaceRaised,
          foregroundColor: c.textPrimary,
          minimumSize: buttonSize,
          shape: buttonShape,
          side: BorderSide(color: c.buttonBorder),
          textStyle: text.labelLarge,
        ),
      ),
      chipTheme: ChipThemeData(
        backgroundColor: c.surfaceHighest,
        labelStyle: text.bodyMedium,
        side: BorderSide.none,
        shape: const StadiumBorder(),
      ),
    );
  }
}
