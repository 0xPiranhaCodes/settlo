import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:settlo_core/settlo_core.dart';

import 'fonts.dart';

void main() {
  setUpAll(loadSettloFonts);

  group('SettloTheme', () {
    test('dark: gold primary on near-black', () {
      final theme = SettloTheme.dark();
      expect(theme.brightness, Brightness.dark);
      expect(theme.colorScheme.primary, const Color(0xFFD8B36A));
      expect(theme.colorScheme.onPrimary, const Color(0xFF0A0B0D));
      expect(theme.scaffoldBackgroundColor, const Color(0xFF0A0B0D));
      expect(theme.extension<SettloColors>(), SettloColors.dark);
    });

    test('light: ink primary on paper', () {
      final theme = SettloTheme.light();
      expect(theme.brightness, Brightness.light);
      expect(theme.colorScheme.primary, const Color(0xFF1B1B18));
      expect(theme.colorScheme.onPrimary, const Color(0xFFF4F1EA));
      expect(theme.scaffoldBackgroundColor, const Color(0xFFF4F1EA));
      expect(theme.extension<SettloColors>(), SettloColors.light);
    });

    test('mint and coral stay out of the colour scheme', () {
      for (final (theme, colors) in [
        (SettloTheme.dark(), SettloColors.dark),
        (SettloTheme.light(), SettloColors.light),
      ]) {
        final scheme = theme.colorScheme;
        final schemeColors = [
          scheme.primary,
          scheme.secondary,
          scheme.tertiary,
          scheme.error,
          scheme.surface,
          scheme.onSurface,
        ];
        expect(
          schemeColors,
          isNot(contains(colors.money(MoneyTone.owedToYou))),
        );
        expect(schemeColors, isNot(contains(colors.money(MoneyTone.youOwe))));
      }
    });

    test('text is Figtree with tabular figures', () {
      final text = SettloTheme.dark().textTheme;
      for (final style in [
        text.bodyLarge!,
        text.labelLarge!,
        text.labelSmall!,
      ]) {
        expect(style.fontFamily, 'packages/settlo_core/Figtree');
        expect(
          style.fontFeatures,
          contains(const FontFeature.tabularFigures()),
        );
      }
      expect(text.bodyLarge!.fontWeight, FontWeight.w400);
      expect(text.labelLarge!.fontWeight, FontWeight.w500);
    });
  });

  group('SettloColors', () {
    test('money tones', () {
      const c = SettloColors.dark;
      expect(c.money(MoneyTone.owedToYou), const Color(0xFF5BD39B));
      expect(c.money(MoneyTone.youOwe), const Color(0xFFF0715C));
      expect(c.money(MoneyTone.settled), c.textSecondary);
      expect(c.money(MoneyTone.neutral), c.textPrimary);
    });

    test('light mint and muted are the contrast-adjusted values', () {
      const c = SettloColors.light;
      expect(c.money(MoneyTone.owedToYou), const Color(0xFF1D7A58));
      expect(c.money(MoneyTone.youOwe), const Color(0xFFB6342B));
      expect(c.textMuted, const Color(0xFF6D6B67));
    });

    test('lerp and copyWith', () {
      const d = SettloColors.dark;
      const l = SettloColors.light;
      expect(d.copyWith(), same(d));
      expect(d.lerp(null, 0.5), same(d));
      expect(d.lerp(l, 0).textPrimary, d.textPrimary);
      final end = d.lerp(l, 1);
      expect(end.background, l.background);
      expect(end.money(MoneyTone.owedToYou), l.money(MoneyTone.owedToYou));
      expect(end.money(MoneyTone.youOwe), l.money(MoneyTone.youOwe));
    });

    testWidgets('of() falls back to dark without a Settlo theme', (
      tester,
    ) async {
      late SettloColors colors;
      await tester.pumpWidget(
        Builder(
          builder: (context) {
            colors = SettloColors.of(context);
            return const SizedBox();
          },
        ),
      );
      expect(colors, SettloColors.dark);
    });
  });

  group('SettloTypography.amount', () {
    test('serif from 20px, Figtree below', () {
      expect(
        SettloTypography.amount(17).fontFamily,
        'packages/settlo_core/Figtree',
      );
      expect(
        SettloTypography.amount(19.9).fontFamily,
        'packages/settlo_core/Figtree',
      );
      final serif = SettloTypography.amount(20);
      expect(serif.fontFamily, 'packages/settlo_core/IBM Plex Serif');
      expect(serif.fontWeight, FontWeight.w500);
      expect(serif.fontFeatures, contains(const FontFeature.tabularFigures()));
      expect(SettloTypography.amount(28).letterSpacing, -0.8);
      expect(SettloTypography.amount(46).letterSpacing, -1);
    });
  });

  group('MoneyText', () {
    Future<void> pump(
      WidgetTester tester,
      Widget child, {
      bool light = false,
    }) => tester.pumpWidget(
      MaterialApp(
        theme: light ? SettloTheme.light() : SettloTheme.dark(),
        home: Scaffold(body: Center(child: child)),
      ),
    );

    testWidgets('list size is one Figtree run in the tone colour', (
      tester,
    ) async {
      await pump(
        tester,
        const MoneyText(Paise(-365000), tone: MoneyTone.youOwe, size: 13),
        light: true,
      );
      final text = tester.widget<Text>(find.byType(Text));
      expect(text.data, '−₹3,650');
      expect(text.style!.fontFamily, 'packages/settlo_core/Figtree');
      expect(text.style!.color, const Color(0xFFB6342B));
    });

    testWidgets('hero size splits a small Figtree ₹ from the serif number', (
      tester,
    ) async {
      await pump(
        tester,
        const MoneyText(Paise.rupees(674200), size: 46, signed: true),
      );
      expect(
        find.bySemanticsLabel(
          'plus six lakh seventy-four thousand two hundred rupees',
        ),
        findsOneWidget,
      );
      final rupee = tester.widget<Text>(find.text('₹'));
      expect(rupee.style!.fontFamily, 'packages/settlo_core/Figtree');
      expect(rupee.style!.fontSize, closeTo(46 * 0.56, 0.001));
      final raise = tester.widget<Transform>(
        find.ancestor(of: find.text('₹'), matching: find.byType(Transform)),
      );
      expect(raise.transform.getTranslation().y, closeTo(-0.26 * 46, 0.001));
      final rich = tester.widget<RichText>(find.byType(RichText).first);
      final span = rich.text as TextSpan;
      expect(span.toPlainText(), startsWith('+'));
      expect(span.toPlainText(), endsWith('6,74,200'));
    });

    testWidgets('the ₹ raise follows the system text scale', (tester) async {
      await pump(
        tester,
        const MediaQuery(
          data: MediaQueryData(textScaler: TextScaler.linear(2)),
          child: MoneyText(Paise.rupees(420), size: 46),
        ),
      );
      final raise = tester.widget<Transform>(
        find.ancestor(of: find.text('₹'), matching: find.byType(Transform)),
      );
      expect(raise.transform.getTranslation().y, closeTo(-0.26 * 92, 0.001));
    });
  });
}
