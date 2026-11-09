import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:settlo_core/settlo_core.dart';

import 'fonts.dart';

const _sizes = [13.0, 17.0, 46.0, 52.0];

void main() {
  setUpAll(loadSettloFonts);

  for (final (name, theme) in [
    ('dark', SettloTheme.dark),
    ('light', SettloTheme.light),
  ]) {
    testWidgets('token sheet, $name', (tester) async {
      await _pump(tester, theme(), const _TokenSheet(), const Size(390, 844));
      await expectGolden(find.byType(_TokenSheet), 'token_sheet_$name');
    });

    testWidgets('MoneyText sizes, $name', (tester) async {
      await _pump(tester, theme(), const _MoneySheet(), const Size(390, 240));
      await expectGolden(find.byType(_MoneySheet), 'money_text_$name');
    });
  }
}

Future<void> _pump(
  WidgetTester tester,
  ThemeData theme,
  Widget child,
  Size size,
) async {
  tester.view
    ..physicalSize = size
    ..devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: theme,
      home: Scaffold(body: child),
    ),
  );
}

class _MoneySheet extends StatelessWidget {
  const new();

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.all(SettloSpacing.screenMargin),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (final size in _sizes)
          Padding(
            padding: const EdgeInsets.only(bottom: SettloSpacing.x1),
            child: Wrap(
              spacing: SettloSpacing.x2,
              crossAxisAlignment: WrapCrossAlignment.end,
              children: [
                MoneyText(const Paise.rupees(674200), size: size, signed: true),
                if (size < 40) ...[
                  MoneyText(
                    const Paise.rupees(2850),
                    tone: MoneyTone.owedToYou,
                    size: size,
                    signed: true,
                  ),
                  MoneyText(
                    const Paise(-365050),
                    tone: MoneyTone.youOwe,
                    size: size,
                  ),
                  MoneyText(Paise.zero, tone: MoneyTone.settled, size: size),
                ],
              ],
            ),
          ),
      ],
    ),
  );
}

class _TokenSheet extends StatelessWidget {
  const new();

  @override
  Widget build(BuildContext context) {
    final c = SettloColors.of(context);
    final text = Theme.of(context).textTheme;
    Widget swatch(String name, Color color) => Column(
      children: [
        Container(
          width: 64,
          height: 40,
          decoration: BoxDecoration(
            color: color,
            borderRadius: BorderRadius.circular(SettloRadius.iconTile),
            border: Border.all(color: c.hairline),
          ),
        ),
        const SizedBox(height: SettloSpacing.half),
        Text(name, style: text.labelSmall),
      ],
    );
    return Padding(
      padding: const EdgeInsets.all(SettloSpacing.screenMargin),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('settlo', style: text.headlineSmall),
          const SizedBox(height: SettloSpacing.x2),
          Wrap(
            spacing: SettloSpacing.x1,
            runSpacing: SettloSpacing.x1,
            children: [
              swatch('background', c.background),
              swatch('surface', c.surface),
              swatch('raised', c.surfaceRaised),
              swatch('highest', c.surfaceHighest),
              swatch('action', c.action),
              swatch('owed', c.money(MoneyTone.owedToYou)),
              swatch('owe', c.money(MoneyTone.youOwe)),
              swatch('settled', c.money(MoneyTone.settled)),
            ],
          ),
          const SizedBox(height: SettloSpacing.x3),
          Card(
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(SettloRadius.cardHero),
              side: BorderSide(color: c.hairline),
            ),
            child: Container(
              width: double.infinity,
              padding: const EdgeInsets.all(22),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(SettloRadius.cardHero),
                border: Border(top: BorderSide(color: c.specular)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'NET POSITION',
                    style: text.labelMedium?.copyWith(color: c.textSecondary),
                  ),
                  const SizedBox(height: SettloSpacing.x1),
                  const MoneyText(Paise.rupees(674200), size: 46, signed: true),
                  const SizedBox(height: 6),
                  Text(
                    'owed to you across 2 spaces and 1 loan',
                    style: text.bodyMedium?.copyWith(color: c.textSecondary),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              Expanded(
                child: FilledButton(
                  onPressed: () {},
                  child: const Text('Add expense'),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: OutlinedButton(
                  onPressed: () {},
                  child: const Text('Settle up'),
                ),
              ),
            ],
          ),
          const SizedBox(height: SettloSpacing.x3),
          Text('Title 17/500', style: text.titleMedium),
          Text('Row title 15/500', style: text.titleSmall),
          Text('Body 15/400 · 0123456789', style: text.bodyLarge),
          Text(
            'Caption 13/400',
            style: text.bodyMedium?.copyWith(color: c.textSecondary),
          ),
          Text(
            'LABEL 12/400',
            style: text.labelMedium?.copyWith(color: c.textSecondary),
          ),
          Text(
            'Tab 11/400 muted',
            style: text.labelSmall?.copyWith(color: c.textMuted),
          ),
          const SizedBox(height: SettloSpacing.x2),
          Row(
            children: [
              const Chip(label: Text('Rent')),
              const SizedBox(width: SettloSpacing.x1),
              Expanded(child: Divider(color: c.hairline)),
            ],
          ),
        ],
      ),
    );
  }
}
