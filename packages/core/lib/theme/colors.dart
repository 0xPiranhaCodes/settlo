import 'package:flutter/material.dart';

/// Which way an amount of money points, for the person looking at it.
///
/// Mint and coral are reachable only through this API: they mean money
/// direction and nothing else.
enum MoneyTone {
  /// Someone owes you (mint).
  owedToYou,

  /// You owe someone (coral).
  youOwe,

  /// Settled up (secondary grey).
  settled,

  /// An amount with no direction, such as a total spend (primary text).
  neutral,
}

/// A text colour on a background colour that the theme allows together.
typedef ContrastPair = ({String name, Color text, Color background});

/// Settlo colour tokens for one theme, from the context pack › Brand and
/// design and the canvas (Main, HomeLight).
///
/// Read with `SettloColors.of(context)`.
@immutable
class SettloColors extends ThemeExtension<SettloColors> {
  const new _({
    required this.background,
    required this.surface,
    required this.surfaceRaised,
    required this.surfaceHighest,
    required this.hairline,
    required this.buttonBorder,
    required this.specular,
    required this.textPrimary,
    required this.textSecondary,
    required this.textMuted,
    required this.action,
    required this.homeGold,
    required this.welcomeAction,
    required this.navActiveStart,
    required this.navActiveEnd,
    required this.onNavActive,
    required this.onAction,
    required this.glass,
    required this.glassFallback,
    required this.glassBorder,
    required this._owedToYou,
    required this._youOwe,
  });

  /// Dark theme, the default.
  static const dark = SettloColors._(
    background: Color(0xFF0A0B0D),
    surface: Color(0xFF15171A),
    surfaceRaised: Color(0xFF1E2126),
    surfaceHighest: Color(0xFF262A30),
    hairline: Color(0x12FFFFFF), // 7% white
    buttonBorder: Color(0x1AFFFFFF), // 10% white
    specular: Color(0x1AFFFFFF), // 10% white
    textPrimary: Color(0xFFF3F2EE),
    textSecondary: Color(0xFF9B9D9A),
    textMuted: Color(0xFF8A8D88),
    action: Color(0xFFD8B36A), // gold
    homeGold: Color(0xFFF2C77F),
    welcomeAction: Color(0xFFF2C77F), // welcome mock's lighter gold
    navActiveStart: Color(0xFF926A30),
    navActiveEnd: Color(0xFF473419),
    onNavActive: Color(0xFFFFFFFF),
    onAction: Color(0xFF0A0B0D),
    glass: Color(0x9E15171A), // 62% surface
    glassFallback: Color(0xEB15171A), // 92% surface
    glassBorder: Color(0x1FFFFFFF), // 12% white
    owedToYou: Color(0xFF5BD39B),
    youOwe: Color(0xFFF0715C),
  );

  /// Light theme. Ink replaces gold as the primary action. Muted and mint
  /// are darkened from the context pack to keep 4.5:1 on every light
  /// surface (canvas note n33; docs/decisions/2026-11-09-light-contrast.md).
  static const light = SettloColors._(
    background: Color(0xFFF4F1EA), // paper
    surface: Color(0xFFFFFFFF),
    surfaceRaised: Color(0xFFF0EDE5),
    surfaceHighest: Color(0xFFE6E2D8),
    hairline: Color(0x141B1B18), // 8% ink
    buttonBorder: Color(0x241B1B18), // 14% ink
    specular: Color(0xE6FFFFFF), // 90% white
    textPrimary: Color(0xFF1B1B18),
    textSecondary: Color(0xFF6B6B66),
    textMuted: Color(0xFF6D6B67), // was #7A7873
    action: Color(0xFF1B1B18), // ink
    homeGold: Color(0xFF76531F),
    welcomeAction: Color(0xFFF2C77F), // fixed dark welcome treatment
    navActiveStart: Color(0xFF926A30),
    navActiveEnd: Color(0xFF473419),
    onNavActive: Color(0xFFFFFFFF),
    onAction: Color(0xFFF4F1EA),
    glass: Color(0x99FFFFFF), // 60% white
    glassFallback: Color(0xEBFFFFFF), // 92% white
    glassBorder: Color(0xBFFFFFFF), // 75% white
    owedToYou: Color(0xFF1D7A58), // was #1E7F5C
    youOwe: Color(0xFFB6342B),
  );

  /// The colours of the nearest [Theme], falling back to [dark].
  static SettloColors of(BuildContext context) =>
      Theme.of(context).extension<SettloColors>() ?? dark;

  /// Screen background.
  final Color background;

  /// Cards.
  final Color surface;

  /// Secondary buttons, icon tiles and inputs on a card.
  final Color surfaceRaised;

  /// Avatars, chips and progress tracks. Carries primary text only.
  final Color surfaceHighest;

  /// 1px card edges and dividers.
  final Color hairline;

  /// 1px edge of a secondary button.
  final Color buttonBorder;

  /// 1px highlight along the top edge of every card.
  final Color specular;

  /// Primary text.
  final Color textPrimary;

  /// Secondary text: labels, captions, settled amounts.
  final Color textSecondary;

  /// Muted text: unselected tabs, hints.
  final Color textMuted;

  /// A tappable primary action: gold in dark, ink in light. Never progress,
  /// ticks, badges or status.
  final Color action;

  /// Home's gold mark, arrows and decorative arcs. The light-theme value is
  /// dark enough to meet text contrast on paper and white cards.
  final Color homeGold;

  /// The owner-approved lighter gold for Welcome's primary button only.
  final Color welcomeAction;

  /// Top-left and bottom-right stops of the active navigation pill.
  final Color navActiveStart;

  /// Bottom-right stop of the active navigation pill.
  final Color navActiveEnd;

  /// Text and icons on the active navigation pill.
  final Color onNavActive;

  /// The lightest stop in Welcome's subtle action gradient.
  Color get welcomeActionTop =>
      Color.alphaBlend(const Color(0x1FFFFFFF), welcomeAction);

  /// The lower stop in Welcome's subtle action gradient.
  Color get welcomeActionBottom =>
      Color.alphaBlend(const Color(0x0A000000), welcomeAction);

  /// A fine highlight along the top edge of Welcome's action.
  Color get welcomeActionHighlight =>
      Color.alphaBlend(const Color(0x66FFFFFF), welcomeAction);

  /// The warm, low shadow beneath Welcome's action.
  Color get welcomeActionShadow => welcomeAction.withValues(alpha: 0.25);

  /// Text and icons on [action].
  final Color onAction;

  /// Floating tab bar fill, behind a 28px blur. Chrome only.
  final Color glass;

  /// Tab bar fill where blur is too costly (mid-range Android).
  final Color glassFallback;

  /// 1px edge of the floating tab bar.
  final Color glassBorder;

  final Color _owedToYou;
  final Color _youOwe;

  /// The colour for an amount with [tone].
  Color money(MoneyTone tone) => switch (tone) {
    MoneyTone.owedToYou => _owedToYou,
    MoneyTone.youOwe => _youOwe,
    MoneyTone.settled => textSecondary,
    MoneyTone.neutral => textPrimary,
  };

  /// Every text colour on every background it may sit on.
  ///
  /// [surfaceHighest] carries primary text only. The glass tab bar is
  /// measured composited over [background].
  List<ContrastPair> get textPairs {
    final backgrounds = {
      'background': background,
      'surface': surface,
      'surfaceRaised': surfaceRaised,
    };
    final texts = {
      'textPrimary': textPrimary,
      'textSecondary': textSecondary,
      'textMuted': textMuted,
      'action': action,
      'homeGold': homeGold,
      for (final tone in MoneyTone.values) 'money.${tone.name}': money(tone),
    };
    final glassOver = Color.alphaBlend(glass, background);
    return [
      for (final bg in backgrounds.entries)
        for (final text in texts.entries)
          (
            name: '${text.key} on ${bg.key}',
            text: text.value,
            background: bg.value,
          ),
      (
        name: 'textPrimary on surfaceHighest',
        text: textPrimary,
        background: surfaceHighest,
      ),
      (name: 'onAction on action', text: onAction, background: action),
      (
        name: 'onNavActive on navActiveStart',
        text: onNavActive,
        background: navActiveStart,
      ),
      (
        name: 'onNavActive on navActiveEnd',
        text: onNavActive,
        background: navActiveEnd,
      ),
      (
        name: 'onAction on welcomeActionTop',
        text: SettloColors.dark.onAction,
        background: welcomeActionTop,
      ),
      (name: 'textPrimary on glass', text: textPrimary, background: glassOver),
      (name: 'textMuted on glass', text: textMuted, background: glassOver),
    ];
  }

  @override
  SettloColors copyWith() => this;

  @override
  SettloColors lerp(SettloColors? other, double t) {
    if (other == null) return this;
    Color l(Color a, Color b) => Color.lerp(a, b, t)!;
    return SettloColors._(
      background: l(background, other.background),
      surface: l(surface, other.surface),
      surfaceRaised: l(surfaceRaised, other.surfaceRaised),
      surfaceHighest: l(surfaceHighest, other.surfaceHighest),
      hairline: l(hairline, other.hairline),
      buttonBorder: l(buttonBorder, other.buttonBorder),
      specular: l(specular, other.specular),
      textPrimary: l(textPrimary, other.textPrimary),
      textSecondary: l(textSecondary, other.textSecondary),
      textMuted: l(textMuted, other.textMuted),
      action: l(action, other.action),
      homeGold: l(homeGold, other.homeGold),
      welcomeAction: l(welcomeAction, other.welcomeAction),
      navActiveStart: l(navActiveStart, other.navActiveStart),
      navActiveEnd: l(navActiveEnd, other.navActiveEnd),
      onNavActive: l(onNavActive, other.onNavActive),
      onAction: l(onAction, other.onAction),
      glass: l(glass, other.glass),
      glassFallback: l(glassFallback, other.glassFallback),
      glassBorder: l(glassBorder, other.glassBorder),
      owedToYou: l(_owedToYou, other._owedToYou),
      youOwe: l(_youOwe, other._youOwe),
    );
  }
}
