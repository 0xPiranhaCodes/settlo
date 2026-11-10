import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:settlo_core/settlo_core.dart';

import '../theme/fonts.dart';

/// A golden per component, dark and light, at 390 and 360 wide.
void main() {
  setUpAll(loadSettloFonts);

  final components = <(String, double, Widget)>[
    ('card', 300, const _Cards()),
    ('buttons', 240, const _Buttons()),
    ('chips', 120, const _Chips()),
    ('segmented', 80, const _Segmented()),
    ('avatar', 80, const _Avatars()),
    ('amount_sheet', 520, const _Sheet()),
    ('tab_bar', 240, const _TabBars()),
  ];

  for (final (theme, data) in [
    ('dark', SettloTheme.dark),
    ('light', SettloTheme.light),
  ]) {
    for (final width in [390.0, 360.0]) {
      for (final (name, height, child) in components) {
        testWidgets('$name, $theme, ${width.toInt()}', (tester) async {
          tester.view
            ..physicalSize = Size(width, height)
            ..devicePixelRatio = 1;
          addTearDown(tester.view.reset);
          await tester.pumpWidget(
            MaterialApp(
              debugShowCheckedModeBanner: false,
              theme: data(),
              home: Scaffold(
                body: RepaintBoundary(
                  key: _golden,
                  // Paint the screen background inside the capture, so
                  // translucent glass and shadows read as on a device.
                  child: Builder(
                    builder: (context) => ColoredBox(
                      color: SettloColors.of(context).background,
                      child: child,
                    ),
                  ),
                ),
              ),
            ),
          );
          await expectGolden(
            find.byKey(_golden),
            '${name}_${theme}_${width.toInt()}',
          );
        });
      }
    }
  }
}

const _golden = Key('golden');

const _margin = EdgeInsets.all(SettloSpacing.screenMargin);

/// A stand-in icon: a stroked circle in the inherited icon colour.
class _Glyph extends StatelessWidget {
  const new();

  @override
  Widget build(BuildContext context) {
    final icon = IconTheme.of(context);
    return CustomPaint(
      size: Size.square(icon.size!),
      painter: _RingPainter(icon.color!),
    );
  }
}

class _RingPainter extends CustomPainter {
  const new(this.color);

  final Color color;

  @override
  void paint(Canvas canvas, Size size) => canvas.drawCircle(
    size.center(Offset.zero),
    size.width * 0.35,
    Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.6,
  );

  @override
  bool shouldRepaint(_RingPainter old) => old.color != color;
}

class _Cards extends StatelessWidget {
  const new();

  @override
  Widget build(BuildContext context) {
    final c = SettloColors.of(context);
    final text = Theme.of(context).textTheme;
    return Padding(
      padding: _margin,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SCard(
            hero: true,
            padding: const EdgeInsets.all(22),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'NET POSITION',
                  style: text.labelMedium?.copyWith(color: c.textSecondary),
                ),
                const SizedBox(height: SettloSpacing.x1),
                const MoneyText(Paise.rupees(674200), size: 46, signed: true),
              ],
            ),
          ),
          const SizedBox(height: 12),
          SCard(
            child: Row(
              children: [
                const SAvatar('Arjun'),
                const SizedBox(width: 14),
                Expanded(
                  child: Text('Arjun · interest free', style: text.bodyLarge),
                ),
                const MoneyText(Paise.rupees(675000)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _Buttons extends StatelessWidget {
  const new();

  @override
  Widget build(BuildContext context) => Padding(
    padding: _margin,
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Expanded(
              child: SPrimaryButton(
                label: 'Add expense',
                icon: const _Glyph(),
                onPressed: () {},
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: SSecondaryButton(label: 'Settle up', onPressed: () {}),
            ),
          ],
        ),
        const SizedBox(height: 12),
        SSecondaryButton(
          label: 'Remind',
          icon: const _Glyph(),
          onPressed: () {},
        ),
        const SizedBox(height: 12),
        const SPrimaryButton(label: 'Save expense', onPressed: null),
      ],
    ),
  );
}

class _Chips extends StatelessWidget {
  const new();

  @override
  Widget build(BuildContext context) => Padding(
    padding: _margin,
    child: Wrap(
      spacing: SettloSpacing.x1,
      children: [
        for (final (i, label) in [
          'All',
          'Needs you',
          'Flat 402',
          'Loans',
        ].indexed)
          SChip(label: label, selected: i == 0, onSelected: (_) {}),
      ],
    ),
  );
}

class _Segmented extends StatelessWidget {
  const new();

  @override
  Widget build(BuildContext context) => Padding(
    padding: _margin,
    child: Align(
      alignment: Alignment.centerLeft,
      child: SSegmentedControl<int>(
        segments: const [
          (value: 0, label: 'Equally'),
          (value: 1, label: 'Exact'),
          (value: 2, label: '%'),
          (value: 3, label: 'Shares'),
        ],
        selected: 0,
        onChanged: (_) {},
      ),
    ),
  );
}

class _Avatars extends StatelessWidget {
  const new();

  @override
  Widget build(BuildContext context) => const Padding(
    padding: _margin,
    child: Row(
      spacing: 12,
      children: [
        SAvatar('Arjun'),
        SAvatar('priya', size: 36),
        SAvatar('Kabir', size: 44),
        SAvatar(''),
      ],
    ),
  );
}

class _Sheet extends StatelessWidget {
  const new();

  @override
  Widget build(BuildContext context) => ColoredBox(
    color: SettloColors.of(context).background,
    child: Padding(
      padding: const EdgeInsets.only(top: 24),
      child: SAmountSheet(
        title: 'New expense · Flat 402',
        amount: const Text('1,800'),
        onClose: () {},
        body: Align(
          alignment: Alignment.topLeft,
          child: Wrap(
            spacing: SettloSpacing.x1,
            children: [
              SChip(label: 'Groceries', selected: true, onSelected: (_) {}),
              SChip(label: 'Utilities', selected: false, onSelected: (_) {}),
            ],
          ),
        ),
        action: SPrimaryButton(
          label: 'Save expense',
          icon: const _Glyph(),
          onPressed: () {},
        ),
      ),
    ),
  );
}

class _TabBars extends StatelessWidget {
  const new();

  static const List<SGlassTab> _tabs = [
    (icon: _Glyph(), label: 'Home'),
    (icon: _Glyph(), label: 'Spaces'),
    (icon: _Glyph(), label: 'Loans'),
    (icon: _Glyph(), label: 'Activity'),
  ];

  @override
  Widget build(BuildContext context) {
    final c = SettloColors.of(context);
    final text = Theme.of(context).textTheme;
    // Content behind the bars, so the blur and the flat fallback differ.
    return Stack(
      children: [
        Positioned.fill(
          child: Padding(
            padding: _margin,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                for (var i = 0; i < 7; i++)
                  Text(
                    'Priya added Electricity in Flat 402',
                    style: text.bodyLarge?.copyWith(
                      color: i.isEven ? c.textPrimary : c.textSecondary,
                    ),
                  ),
              ],
            ),
          ),
        ),
        Positioned(
          left: 16,
          right: 16,
          top: 16,
          child: SGlassTabBar(tabs: _tabs, currentIndex: 0, onTap: (_) {}),
        ),
        Positioned(
          left: 16,
          right: 16,
          top: 116,
          child: SGlassTabBar(
            tabs: _tabs,
            currentIndex: 3,
            lowEndBlur: true,
            onTap: (_) {},
          ),
        ),
      ],
    );
  }
}
