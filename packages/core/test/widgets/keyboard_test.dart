import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:settlo_core/settlo_core.dart';

const List<SGlassTab> _tabs = [
  (icon: SizedBox.square(dimension: 22), label: 'Home'),
  (icon: SizedBox.square(dimension: 22), label: 'Activity'),
];

/// Every custom control in one column, in reading order.
Widget _controls(List<String> log) => Column(
  children: [
    SizedBox(
      height: 220,
      child: SAmountSheet(
        title: 'New expense',
        amount: const Text('1,800'),
        onClose: () => log.add('close'),
      ),
    ),
    Row(
      children: [
        SChip(
          label: 'Food',
          selected: true,
          onSelected: (v) => log.add('chip $v'),
        ),
      ],
    ),
    SSegmentedControl<String>(
      segments: const [
        (value: 'eq', label: 'Equally'),
        (value: 'pc', label: '%'),
      ],
      selected: 'eq',
      onChanged: (v) => log.add('segment $v'),
    ),
    SGlassTabBar(tabs: _tabs, currentIndex: 0, onTap: (i) => log.add('tab $i')),
  ],
);

Future<void> _pump(WidgetTester tester, List<String> log) async {
  tester.view
    ..physicalSize = const Size(390, 844)
    ..devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    MaterialApp(
      theme: SettloTheme.dark(),
      home: Scaffold(body: _controls(log)),
    ),
  );
}

/// The label of the control that holds focus, from its semantics.
String _focusedLabel(WidgetTester tester) {
  final focused = FocusManager.instance.primaryFocus!.context!;
  return tester.getSemantics(find.byWidget(focused.widget).first).label;
}

void main() {
  testWidgets('Tab moves focus through the controls in reading order', (
    tester,
  ) async {
    await _pump(tester, []);
    final order = <String>[];
    for (var i = 0; i < 6; i++) {
      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await tester.pump();
      order.add(_focusedLabel(tester));
    }
    expect(order, ['Close', 'Food', 'Equally', '%', 'Home', 'Activity']);
  });

  for (final key in [LogicalKeyboardKey.enter, LogicalKeyboardKey.space]) {
    testWidgets('${key.keyLabel} activates the focused control', (
      tester,
    ) async {
      final log = <String>[];
      await _pump(tester, log);
      for (var i = 0; i < 6; i++) {
        await tester.sendKeyEvent(LogicalKeyboardKey.tab);
        await tester.sendKeyEvent(key);
        await tester.pump();
      }
      expect(log, [
        'close',
        'chip false',
        'segment eq',
        'segment pc',
        'tab 0',
        'tab 1',
      ]);
    });
  }

  testWidgets('keyboard focus draws a primary-text ring, never gold', (
    tester,
  ) async {
    await _pump(tester, []);
    BoxDecoration ring() =>
        tester
                .widget<DecoratedBox>(
                  find
                      .descendant(
                        of: find.byType(SChip),
                        matching: find.byType(DecoratedBox),
                      )
                      .first,
                )
                .decoration
            as BoxDecoration;

    expect(ring().border, isNull);
    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    await tester.pump();
    final border = ring().border! as Border;
    expect(border.top.color, SettloColors.dark.textPrimary);
    expect(border.top.color, isNot(SettloColors.dark.action));
  });

  testWidgets('controls report button, selected, focusable and a label', (
    tester,
  ) async {
    final handle = tester.ensureSemantics();
    await _pump(tester, []);
    expect(
      tester.getSemantics(find.bySemanticsLabel('Close')),
      matchesSemantics(
        label: 'Close',
        isButton: true,
        isFocusable: true,
        hasTapAction: true,
        hasFocusAction: true,
      ),
    );
    for (final (label, selected) in [
      ('Food', true),
      ('Equally', true),
      ('%', false),
      ('Home', true),
      ('Activity', false),
    ]) {
      expect(
        tester.getSemantics(find.bySemanticsLabel(label)),
        matchesSemantics(
          label: label,
          isButton: true,
          hasSelectedState: true,
          isSelected: selected,
          isFocusable: true,
          hasTapAction: true,
          hasFocusAction: true,
        ),
        reason: label,
      );
    }
    handle.dispose();
  });
}
