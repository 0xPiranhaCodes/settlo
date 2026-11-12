import 'package:flutter/material.dart';

/// Which way an amount of money points, for the person looking at it.
///
/// Money direction has explicit semantic colours in each appearance.
enum MoneyTone {
  /// Someone owes you.
  owedToYou,

  /// You owe someone.
  youOwe,

  /// Settled up (secondary grey).
  settled,

  /// An amount with no direction, such as a total spend (primary text).
  neutral,
}

/// A text colour on a background colour that the theme allows together.
typedef ContrastPair = ({String name, Color text, Color background});

/// Owner-supplied Settle Check semantic palette (issue #202).
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
    required this.pending,
    required this.error,
    required this.brandAccent,
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
    background: Color(0xFF000000),
    surface: Color(0xFF14271C),
    surfaceRaised: Color(0xFF1A3023),
    surfaceHighest: Color(0xFF244332),
    hairline: Color(0xFF30473C),
    buttonBorder: Color(0xFF688778),
    specular: Color(0xFF30473C),
    textPrimary: Color(0xFFF7F2E8),
    textSecondary: Color(0xFFA9BCB0),
    textMuted: Color(0xFFA9BCB0),
    action: Color(0xFFFEBD11),
    brandAccent: Color(0xFFFEBD11),
    welcomeAction: Color(0xFFFEBD11),
    navActiveStart: Color(0xFFFEBD11),
    navActiveEnd: Color(0xFFFEBD11),
    onNavActive: Color(0xFF01381E),
    onAction: Color(0xFF01381E),
    glass: Color(0x9E14271C),
    glassFallback: Color(0xEB14271C),
    glassBorder: Color(0xFF30473C),
    owedToYou: Color(0xFF83DDA1),
    youOwe: Color(0xFFF2AB98),
    pending: Color(0xFFF1C874),
    error: Color(0xFFFF9CA3),
  );

  /// Light theme: ivory surfaces and jade actions.
  static const light = SettloColors._(
    background: Color(0xFFFBF8EF),
    surface: Color(0xFFFFFDF8),
    surfaceRaised: Color(0xFFF6F1E5),
    surfaceHighest: Color(0xFFE8EDDE),
    hairline: Color(0xFFD8E0D8),
    buttonBorder: Color(0xFF708478),
    specular: Color(0xFFD8E0D8),
    textPrimary: Color(0xFF18271F),
    textSecondary: Color(0xFF50645A),
    textMuted: Color(0xFF50645A),
    action: Color(0xFF01672D),
    brandAccent: Color(0xFF01672D),
    welcomeAction: Color(0xFF01672D),
    navActiveStart: Color(0xFF01672D),
    navActiveEnd: Color(0xFF01672D),
    onNavActive: Color(0xFFFEF0CE),
    onAction: Color(0xFFFEF0CE),
    glass: Color(0x99FFFDF8),
    glassFallback: Color(0xEBFFFDF8),
    glassBorder: Color(0xFFD8E0D8),
    owedToYou: Color(0xFF01672D),
    youOwe: Color(0xFF934636),
    pending: Color(0xFF795309),
    error: Color(0xFFA42E35),
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

  /// A primary action: marigold in dark, jade in light.
  final Color action;

  /// Waiting for confirmation; pair with a clock icon.
  final Color pending;

  /// Failed validation or operation.
  final Color error;

  /// Brand accent for decorative arcs, charts and navigation.
  final Color brandAccent;

  /// Welcome uses the same primary action as the rest of the app.
  final Color welcomeAction;

  /// Top-left and bottom-right stops of the active navigation pill.
  final Color navActiveStart;

  /// Bottom-right stop of the active navigation pill.
  final Color navActiveEnd;

  /// Text and icons on the active navigation pill.
  final Color onNavActive;

  /// The lightest stop in Welcome's subtle action gradient.
  Color get welcomeActionTop => welcomeAction;

  /// The lower stop in Welcome's subtle action gradient.
  Color get welcomeActionBottom => welcomeAction;

  /// A fine highlight along the top edge of Welcome's action.
  Color get welcomeActionHighlight =>
      Color.alphaBlend(const Color(0x66FEF0CE), welcomeAction);

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
      'pending': pending,
      'error': error,
      'brandAccent': brandAccent,
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
        text: onAction,
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
      pending: l(pending, other.pending),
      error: l(error, other.error),
      brandAccent: l(brandAccent, other.brandAccent),
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
