import 'dart:ui' show ImageFilter;

import 'package:flutter/widgets.dart';

/// Spacing on the 8pt grid. [half] is for tight optical gaps only.
abstract final class SettloSpacing {
  /// 4.
  static const double half = 4;

  /// 8.
  static const double x1 = 8;

  /// 16.
  static const double x2 = 16;

  /// 24.
  static const double x3 = 24;

  /// 32.
  static const double x4 = 32;

  /// 40.
  static const double x5 = 40;

  /// 48.
  static const double x6 = 48;

  /// Left and right screen margin.
  static const double screenMargin = 20;

  /// Minimum touch target, in both directions.
  static const double minTouchTarget = 44;
}

/// Shared motion; callers suppress animation when Reduce Motion is enabled.
abstract final class SettloMotion {
  /// Short press response.
  static const press = Duration(milliseconds: 150);

  /// Panels and content transitions.
  static const panel = Duration(milliseconds: 200);

  /// Sliding selection pill.
  static const selection = Duration(milliseconds: 250);

  /// Native deceleration without bounce.
  static const Curve curve = Curves.easeOutCubic;

  /// Subtle compression while held.
  static const double pressedScale = 0.97;
}

/// Corner radii.
abstract final class SettloRadius {
  /// Compact nested controls.
  static const double compact = 12;

  /// List cards.
  static const double card = 24;

  /// The hero card on a screen.
  static const double cardHero = 28;

  /// Buttons.
  static const double button = 16;

  /// 40px icon tiles in list rows.
  static const double iconTile = 14;

  /// Chips, the tab bar and anything else fully rounded.
  static const double pill = 999;
}

/// Measurements unique to the owner-approved welcome composition.
///
/// They live with the design-system tokens so the screen does not grow a
/// second, private set of visual constants.
abstract final class SettloWelcomeMetrics {
  /// Owner-approved mock exception to the standard 20px screen margin.
  static const double screenMargin = 24;

  /// Circular portrait and letter-tile diameter.
  static const double avatar = 52;

  /// How far adjacent portraits overlap.
  static const double avatarOverlap = 9;

  /// Stroke around portraits, the letter tile and the add ring.
  static const double avatarRing = 1.25;

  /// Height of each illustrative ledger card at the default text scale.
  static const double exampleCardHeight = 68;

  /// Radius of the illustrative ledger cards.
  static const double exampleCardRadius = 24;

  /// Scale while Welcome's primary action is held.
  static const double actionPressedScale = 0.97;

  /// Horizontal arrow travel while Welcome's primary action is held.
  static const double actionArrowNudge = 3;

  /// Duration of Welcome's short press response.
  static const Duration actionPressDuration = SettloMotion.press;

  /// Blur radius of the warm shadow beneath Welcome's primary action.
  static const double actionShadowBlur = 24;

  /// Downward offset of the warm shadow beneath Welcome's primary action.
  static const double actionShadowOffset = 8;
}

/// Measurements unique to the owner-approved Home composition.
abstract final class SettloHomeMetrics {
  /// Diameter of the circular header controls.
  static const double headerControl = 44;

  /// Diameter of the gold arrow control on an empty-state action card.
  static const double arrowButton = 44;
}

/// Shared micro-borders and soft layered ambient elevation.
abstract final class SettloElevation {
  /// Width of card edges, dividers and the specular highlight.
  static const double hairline = 1;

  /// Shared blur and saturation for floating and pinned glass chrome.
  static ImageFilter get glassFilter => ImageFilter.compose(
    // A restrained saturation lift of the backdrop only.
    outer: const ColorFilter.matrix([
      1.118,
      -0.107,
      -0.011,
      0,
      0,
      -0.032,
      1.043,
      -0.011,
      0,
      0,
      -0.032,
      -0.107,
      1.139,
      0,
      0,
      0,
      0,
      0,
      1,
      0,
    ]),
    inner: ImageFilter.blur(
      sigmaX: SettloElevation.glassBlur,
      sigmaY: SettloElevation.glassBlur,
    ),
  );

  /// Glass tint leaves the backdrop visible outside the legibility plates.
  static const double glassTint = 0.42;

  /// Local backing under navigation glyphs, never the entire capsule.
  static const double glassLegibility = 0.72;

  /// Low-opacity neutral card edge, without changing palette hues.
  static Color border({required bool dark}) =>
      dark ? const Color(0x14FFFFFF) : const Color(0x0F000000);

  /// A broad ambient layer and a close contact layer.
  static List<BoxShadow> ambient({required bool dark}) => [
    BoxShadow(
      color: Color(dark ? 0x14000000 : 0x0A000000),
      offset: const Offset(0, 4),
      blurRadius: 16,
    ),
    BoxShadow(
      color: Color(dark ? 0x0A000000 : 0x05000000),
      offset: const Offset(0, 1),
      blurRadius: 4,
    ),
  ];

  /// Floating tab bar height.
  static const double tabBarHeight = 68;

  /// Blur behind the floating tab bar. Never behind content or amounts.
  static const double glassBlur = 28;

  /// Shadow under the floating tab bar, dark theme.
  static const floatingDark = [
    BoxShadow(color: Color(0x24000000), offset: Offset(0, 8), blurRadius: 24),
    BoxShadow(color: Color(0x14000000), offset: Offset(0, 2), blurRadius: 8),
  ];

  /// Shadow under the floating tab bar, light theme.
  static const floatingLight = [
    BoxShadow(color: Color(0x101B1B18), offset: Offset(0, 8), blurRadius: 24),
    BoxShadow(color: Color(0x081B1B18), offset: Offset(0, 2), blurRadius: 8),
  ];
}
