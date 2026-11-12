import 'package:flutter/material.dart';
import 'package:settlo_core/theme/colors.dart';
import 'package:settlo_core/theme/tokens.dart';
import 'package:settlo_core/theme/typography.dart';
import 'package:settlo_core/widgets/platform_page.dart';
import 'package:settlo_core/widgets/pressable.dart';

/// Settlo [ThemeData]. Dark is the default.
abstract final class SettloTheme {
  /// Dark theme: marigold primary action.
  static ThemeData dark() => _build(SettloColors.dark, Brightness.dark);

  /// Light theme: jade primary action.
  static ThemeData light() => _build(SettloColors.light, Brightness.light);

  static ThemeData _build(SettloColors c, Brightness brightness) {
    final text = SettloTypography.textTheme(c.textPrimary);
    final scheme = ColorScheme(
      brightness: brightness,
      primary: c.action,
      onPrimary: c.onAction,
      secondary: c.surfaceHighest,
      onSecondary: c.textPrimary,
      error: c.error,
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
      pageTransitionsTheme: PageTransitionsTheme(
        builders: {
          for (final platform in TargetPlatform.values)
            platform: const SettloPageTransitionsBuilder(),
        },
      ),
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
      // Material controls share the same action/label pair as iOS.
      checkboxTheme: CheckboxThemeData(
        fillColor: _selected(c.action, Colors.transparent),
        checkColor: WidgetStatePropertyAll(c.onAction),
        side: BorderSide(color: c.textSecondary, width: 1.5),
      ),
      radioTheme: RadioThemeData(
        fillColor: _selected(c.action, c.buttonBorder),
      ),
      switchTheme: SwitchThemeData(
        thumbColor: _selected(c.onAction, c.textSecondary),
        trackColor: _selected(c.action, c.surfaceHighest),
        trackOutlineColor: _selected(c.action, c.buttonBorder),
      ),
      sliderTheme: SliderThemeData(
        activeTrackColor: c.brandAccent,
        inactiveTrackColor: c.surfaceHighest,
        thumbColor: c.action,
        overlayColor: c.hairline,
        valueIndicatorColor: c.surfaceHighest,
      ),
      progressIndicatorTheme: ProgressIndicatorThemeData(
        color: c.brandAccent,
        linearTrackColor: c.surfaceHighest,
        circularTrackColor: c.surfaceHighest,
      ),
      textSelectionTheme: TextSelectionThemeData(
        cursorColor: c.textPrimary,
        selectionColor: c.textSecondary.withValues(alpha: 0.4),
        selectionHandleColor: c.textPrimary,
      ),
      iconButtonTheme: const IconButtonThemeData(
        style: ButtonStyle(
          minimumSize: WidgetStatePropertyAll(Size(44, 44)),
          foregroundBuilder: _pressFeedback,
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: c.textPrimary,
          minimumSize: const Size(44, 44),
          textStyle: text.labelLarge,
        ).copyWith(foregroundBuilder: _pressFeedback),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: c.surfaceRaised,
        hintStyle: text.bodyLarge?.copyWith(color: c.textMuted),
        floatingLabelStyle: TextStyle(color: c.textSecondary),
        enabledBorder: _inputBorder(c.buttonBorder),
        focusedBorder: _inputBorder(c.textPrimary),
        border: _inputBorder(c.buttonBorder),
      ),
      chipTheme: ChipThemeData(
        backgroundColor: c.surfaceHighest,
        labelStyle: text.bodyMedium,
        side: BorderSide.none,
        shape: const StadiumBorder(),
      ),
    );
  }

  static Widget _pressFeedback(
    BuildContext context,
    Set<WidgetState> states,
    Widget? child,
  ) => SPressFeedback(
    enabled: !states.contains(WidgetState.disabled),
    pressed: states.contains(WidgetState.pressed),
    child: child ?? const SizedBox.shrink(),
  );

  static WidgetStateProperty<Color> _selected(Color on, Color off) =>
      WidgetStateProperty.resolveWith(
        (states) => states.contains(WidgetState.selected) ? on : off,
      );

  static OutlineInputBorder _inputBorder(Color color) => OutlineInputBorder(
    borderRadius: const BorderRadius.all(Radius.circular(SettloRadius.button)),
    borderSide: BorderSide(color: color),
  );
}
