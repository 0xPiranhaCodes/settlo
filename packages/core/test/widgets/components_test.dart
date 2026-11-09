import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:settlo_core/settlo_core.dart';

Future<void> _pump(WidgetTester tester, Widget child) => tester.pumpWidget(
  MaterialApp(
    theme: SettloTheme.dark(),
    home: Scaffold(body: Center(child: child)),
  ),
);

const List<SGlassTab> _tabs = [
  (icon: SizedBox.square(dimension: 22), label: 'Home'),
  (icon: SizedBox.square(dimension: 22), label: 'Spaces'),
  (icon: SizedBox.square(dimension: 22), label: 'Activity'),
];

void main() {
  testWidgets('buttons call onPressed and are at least 44pt tall', (
    tester,
  ) async {
    final taps = <String>[];
    await _pump(
      tester,
      Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          SPrimaryButton(label: 'Add', onPressed: () => taps.add('primary')),
          SSecondaryButton(
            label: 'Settle',
            icon: const Icon(null),
            onPressed: () => taps.add('secondary'),
          ),
        ],
      ),
    );
    await tester.tap(find.text('Add'));
    await tester.tap(find.text('Settle'));
    expect(taps, ['primary', 'secondary']);
    for (final type in [FilledButton, OutlinedButton]) {
      final size = tester.getSize(find.byType(type));
      expect(size.height, greaterThanOrEqualTo(SettloSpacing.minTouchTarget));
    }
  });

  testWidgets('a chip toggles and has a 44pt target', (tester) async {
    bool? value;
    await _pump(
      tester,
      SChip(label: 'Food', selected: false, onSelected: (v) => value = v),
    );
    expect(
      tester.getSize(find.byType(SChip)).height,
      SettloSpacing.minTouchTarget,
    );
    // The band above the 36px pill still counts as the chip.
    final top = tester.getTopLeft(find.byType(SChip));
    await tester.tapAt(top + const Offset(24, 2));
    expect(value, isTrue);
  });

  testWidgets('a segmented control reports the tapped value', (tester) async {
    int? value;
    await _pump(
      tester,
      SSegmentedControl<int>(
        segments: const [(value: 0, label: 'Equally'), (value: 1, label: '%')],
        selected: 0,
        onChanged: (v) => value = v,
      ),
    );
    expect(
      tester.getSize(find.byType(SSegmentedControl<int>)).height,
      SettloSpacing.minTouchTarget,
    );
    final segment = find.text('%');
    await tester.tapAt(
      Offset(
        tester.getCenter(segment).dx,
        tester.getTopLeft(find.byType(SSegmentedControl<int>)).dy + 2,
      ),
    );
    expect(value, 1);
  });

  testWidgets('a blank amount shows ₹— in grey and reads as unknown', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();
    await _pump(
      tester,
      const Column(
        mainAxisSize: MainAxisSize.min,
        children: [MoneyText.blank(), MoneyText.blank(size: 46)],
      ),
    );
    expect(find.text('₹—'), findsOneWidget);
    expect(find.bySemanticsLabel('not known yet'), findsOneWidget);
    final small = tester.widget<Text>(find.text('₹—'));
    expect(small.style?.color, SettloColors.dark.textSecondary);
    semantics.dispose();
  });

  testWidgets('an avatar shows an initial, or ? for no name', (tester) async {
    await _pump(
      tester,
      Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (final name in ['  priya', '']) SAvatar(name),
        ],
      ),
    );
    expect(find.text('P'), findsOneWidget);
    expect(find.text('?'), findsOneWidget);
    expect(find.bySemanticsLabel('  priya'), findsOneWidget);
  });

  testWidgets('the tab bar is 68 tall, reports taps and blurs only when '
      'allowed', (tester) async {
    int? tapped;
    Future<void> pumpBar({required bool lowEndBlur}) => _pump(
      tester,
      SGlassTabBar(
        tabs: _tabs,
        currentIndex: 0,
        lowEndBlur: lowEndBlur,
        onTap: (i) => tapped = i,
      ),
    );

    await pumpBar(lowEndBlur: false);
    expect(
      tester.getSize(find.byType(SGlassTabBar)).height,
      SettloElevation.tabBarHeight,
    );
    final filter = tester.widget<BackdropFilter>(find.byType(BackdropFilter));
    expect(filter.filter, isNotNull);
    await tester.tap(find.text('Activity'));
    expect(tapped, 2);

    await pumpBar(lowEndBlur: true);
    expect(find.byType(BackdropFilter), findsNothing);
    final fill = tester
        .widgetList<Container>(
          find.descendant(
            of: find.byType(SGlassTabBar),
            matching: find.byType(Container),
          ),
        )
        .map((c) => (c.decoration as BoxDecoration?)?.color)
        .first;
    expect(fill, SettloColors.dark.glassFallback);
  });

  testWidgets('the amount sheet opens as a modal and closes', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: SettloTheme.light(),
        home: Builder(
          builder: (context) => Scaffold(
            body: TextButton(
              onPressed: () => showSAmountSheet<void>(
                context: context,
                builder: (context) => SAmountSheet(
                  title: 'New loan',
                  amount: const Text('25,000'),
                  onClose: () => Navigator.pop(context),
                ),
              ),
              child: const Text('Open'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();
    expect(find.text('New loan'), findsOneWidget);
    expect(find.text('AMOUNT'), findsOneWidget);

    // The amount is first and in the serif.
    final amount = tester.widget<DefaultTextStyle>(
      find
          .ancestor(
            of: find.text('25,000'),
            matching: find.byType(DefaultTextStyle),
          )
          .first,
    );
    expect(amount.style.fontFamily, contains(SettloTypography.serifFamily));
    expect(
      tester.getTopLeft(find.text('25,000')).dy,
      lessThan(tester.getTopLeft(find.text('AMOUNT')).dy + 40),
    );

    await tester.tap(find.bySemanticsLabel('Close'));
    await tester.pumpAndSettle();
    expect(find.text('New loan'), findsNothing);
  });

  testWidgets('the close icon repaints when the theme changes', (tester) async {
    Future<void> pumpSheet(ThemeData theme) => tester.pumpWidget(
      MaterialApp(
        theme: theme,
        home: SAmountSheet(
          title: 'Settle up',
          amount: const Text('2,100'),
          onClose: () {},
        ),
      ),
    );
    await pumpSheet(SettloTheme.dark());
    await pumpSheet(SettloTheme.light());
    final painter = tester
        .widgetList<CustomPaint>(find.byType(CustomPaint))
        .map((p) => p.painter)
        .whereType<CustomPainter>()
        .where((p) => p.runtimeType.toString() == '_CrossPainter');
    expect(painter, hasLength(1));
  });
}
