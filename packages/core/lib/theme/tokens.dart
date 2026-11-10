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

/// Corner radii.
abstract final class SettloRadius {
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
  static const Duration actionPressDuration = Duration(milliseconds: 90);

  /// Blur radius of the warm shadow beneath Welcome's primary action.
  static const double actionShadowBlur = 24;

  /// Downward offset of the warm shadow beneath Welcome's primary action.
  static const double actionShadowOffset = 8;
}

/// Depth. Cards get no drop shadow: a hairline edge plus a 1px specular
/// highlight along the top. Only floating chrome casts a shadow.
abstract final class SettloElevation {
  /// Width of card edges, dividers and the specular highlight.
  static const double hairline = 1;

  /// Floating tab bar height.
  static const double tabBarHeight = 68;

  /// Blur behind the floating tab bar. Never behind content or amounts.
  static const double glassBlur = 28;

  /// Shadow under the floating tab bar, dark theme.
  static const floatingDark = [
    BoxShadow(color: Color(0x73000000), offset: Offset(0, 24), blurRadius: 48),
  ];

  /// Shadow under the floating tab bar, light theme.
  static const floatingLight = [
    BoxShadow(color: Color(0x1A1B1B18), offset: Offset(0, 20), blurRadius: 40),
  ];
}
