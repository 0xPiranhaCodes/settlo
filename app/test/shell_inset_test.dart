import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:settlo/shell.dart';
import 'package:settlo_core/settlo_core.dart';

import 'package:settlo_test_support/golden.dart';

const _bottomAction = Key('bottom-action');
const _lastRow = Key('last-row');

/// Pumps the shell over [screen] on [device], with [viewPadding] as the
/// device's own bottom inset.
Future<void> _pump(
  WidgetTester tester,
  GoldenDevice device,
  Widget screen, {
  double viewPadding = 0,
}) async {
  tester.view
    ..physicalSize = device.size
    ..devicePixelRatio = 1
    ..viewPadding = FakeViewPadding(bottom: viewPadding)
    ..padding = FakeViewPadding(bottom: viewPadding);
  addTearDown(tester.view.reset);
  tester.platformDispatcher.textScaleFactorTestValue = device.textScale;
  addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
  await tester.pumpWidget(
    MaterialApp(
      theme: SettloTheme.dark(),
      home: SettloShell(currentIndex: 0, onTabSelected: (_) {}, child: screen),
    ),
  );
}

double _barTop(WidgetTester tester) =>
    tester.getRect(find.byType(SGlassTabBar)).top;

void main() {
  for (final device in SettloGoldenDevices.accessible) {
    for (final viewPadding in [0.0, 34.0, 48.0]) {
      final label = '${device.name}, device inset $viewPadding';

      testWidgets('fixed content in a SafeArea clears the tab bar, $label', (
        tester,
      ) async {
        await _pump(
          tester,
          device,
          viewPadding: viewPadding,
          const Scaffold(
            body: SafeArea(
              child: Align(
                alignment: Alignment.bottomCenter,
                child: SizedBox(key: _bottomAction, height: 50, width: 200),
              ),
            ),
          ),
        );
        expect(
          tester.getRect(find.byKey(_bottomAction)).bottom,
          lessThanOrEqualTo(_barTop(tester)),
        );
      });

      testWidgets('a scrolled-to-end list clears the tab bar, $label', (
        tester,
      ) async {
        await _pump(
          tester,
          device,
          viewPadding: viewPadding,
          Scaffold(
            body: ListView(
              children: [
                for (var i = 0; i < 40; i++)
                  SizedBox(
                    key: i == 39 ? _lastRow : null,
                    height: 64,
                    child: Text('Row $i'),
                  ),
              ],
            ),
          ),
        );
        await tester.drag(find.byType(ListView), const Offset(0, -5000));
        await tester.pumpAndSettle();
        expect(
          tester.getRect(find.byKey(_lastRow)).bottom,
          lessThanOrEqualTo(_barTop(tester)),
        );
      });
    }
  }
}
