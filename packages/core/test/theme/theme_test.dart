import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:settlo_core/settlo_core.dart';

import 'fonts.dart';

void main() {
  setUpAll(loadSettloFonts);

  group('SettloTheme', () {
    test('dark: marigold primary on black', () {
      final theme = SettloTheme.dark();
      expect(theme.brightness, Brightness.dark);
      expect(theme.colorScheme.primary, const Color(0xFFFEBD11));
      expect(theme.colorScheme.onPrimary, const Color(0xFF01381E));
      expect(theme.scaffoldBackgroundColor, const Color(0xFF000000));
      expect(theme.extension<SettloColors>(), SettloColors.dark);
    });

    test('light: jade primary on ivory', () {
      final theme = SettloTheme.light();
      expect(theme.brightness, Brightness.light);
      expect(theme.colorScheme.primary, const Color(0xFF01672D));
      expect(theme.colorScheme.onPrimary, const Color(0xFFFEF0CE));
      expect(theme.scaffoldBackgroundColor, const Color(0xFFFBF8EF));
      expect(theme.extension<SettloColors>(), SettloColors.light);
    });

    test('errors use the supplied semantic role in Material', () {
      expect(SettloTheme.light().colorScheme.error, const Color(0xFFA42E35));
      expect(SettloTheme.dark().colorScheme.error, const Color(0xFFFF9CA3));
    });

    test('switch thumb stays neutral in dark and unchanged in light', () {
      expect(
        SettloTheme.dark().switchTheme.thumbColor!.resolve({
          WidgetState.selected,
        }),
        SettloColors.dark.background,
      );
      expect(
        SettloTheme.light().switchTheme.thumbColor!.resolve({
          WidgetState.selected,
        }),
        SettloColors.light.onAction,
      );
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
      expect(text.labelLarge!.fontWeight, FontWeight.w600);
    });
  });

  group('SettloColors', () {
    test('owner role table is exact in both appearances', () {
      List<Color> roles(SettloColors c) => [
        c.background,
        c.surface,
        c.textPrimary,
        c.textSecondary,
        c.action,
        c.onAction,
        c.hairline,
        c.buttonBorder,
        c.money(MoneyTone.owedToYou),
        c.money(MoneyTone.youOwe),
        c.pending,
        c.error,
      ];
      expect(
        roles(SettloColors.light),
        [
          0xFFFBF8EF,
          0xFFFFFDF8,
          0xFF18271F,
          0xFF50645A,
          0xFF01672D,
          0xFFFEF0CE,
          0xFFD8E0D8,
          0xFF708478,
          0xFF01672D,
          0xFF934636,
          0xFF795309,
          0xFFA42E35,
        ].map(Color.new).toList(),
      );
      expect(
        roles(SettloColors.dark),
        [
          0xFF000000,
          0xFF1C1C1E,
          0xFFF7F2E8,
          0xFFB8B8B8,
          0xFFFEBD11,
          0xFF01381E,
          0xFF48484A,
          0xFF858585,
          0xFFFEBD11,
          0xFFF2AB98,
          0xFFB8B8B8,
          0xFFFF9CA3,
        ].map(Color.new).toList(),
      );
    });

    test('money tones', () {
      const c = SettloColors.dark;
      expect(c.money(MoneyTone.owedToYou), const Color(0xFFFEBD11));
      expect(c.money(MoneyTone.youOwe), const Color(0xFFF2AB98));
      expect(c.money(MoneyTone.settled), c.textSecondary);
      expect(c.money(MoneyTone.neutral), c.textPrimary);
    });

    test('light mint and muted are the contrast-adjusted values', () {
      const c = SettloColors.light;
      expect(c.money(MoneyTone.owedToYou), const Color(0xFF01672D));
      expect(c.money(MoneyTone.youOwe), const Color(0xFF934636));
      expect(c.textMuted, const Color(0xFF50645A));
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
    test('uses Figtree with tabular figures at every size', () {
      for (final size in [17.0, 19.9, 20.0, 28.0, 46.0]) {
        final amount = SettloTypography.amount(size);
        expect(amount.fontFamily, 'packages/settlo_core/Figtree');
        expect(amount.fontWeight, FontWeight.w500);
        expect(
          amount.fontFeatures,
          contains(const FontFeature.tabularFigures()),
        );
      }
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
      expect(text.style!.color, const Color(0xFF934636));
    });

    testWidgets('hero size uses Figtree with the mock-size ₹', (tester) async {
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
      expect(rupee.style!.fontSize, closeTo(46 * 0.66, 0.001));
      final raise = tester.widget<Transform>(
        find.ancestor(of: find.text('₹'), matching: find.byType(Transform)),
      );
      expect(raise.transform.getTranslation().y, closeTo(-0.26 * 46, 0.001));
      final rich = tester.widget<RichText>(find.byType(RichText).first);
      final span = rich.text as TextSpan;
      expect(span.toPlainText(), startsWith('+'));
      expect(span.toPlainText(), endsWith('6,74,200'));
    });

    testWidgets('the ₹ raise is scaled once by its parent span', (
      tester,
    ) async {
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
      expect(raise.transform.getTranslation().y, closeTo(-0.26 * 46, 0.001));
    });
  });
}
