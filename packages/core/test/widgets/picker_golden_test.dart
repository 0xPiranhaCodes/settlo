import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:settlo_core/settlo_core.dart';
import 'package:settlo_test_support/golden.dart';

void main() {
  for (final device in SettloGoldenDevices.all) {
    for (final light in [false, true]) {
      for (final date in [false, true]) {
        final name =
            '${date ? 'date' : 'value'}_picker_${device.name}_'
            '${light ? 'light' : 'dark'}';
        testWidgets('$name selected row remains readable', (tester) async {
          await loadSettloFonts();
          tester.view
            ..physicalSize = device.size
            ..devicePixelRatio = 1;
          addTearDown(tester.view.resetPhysicalSize);
          addTearDown(tester.view.resetDevicePixelRatio);
          await tester.pumpWidget(
            RepaintBoundary(
              key: settloGoldenSurfaceKey,
              child: MaterialApp(
                debugShowCheckedModeBanner: false,
                theme: (light ? SettloTheme.light() : SettloTheme.dark())
                    .copyWith(platform: TargetPlatform.iOS),
                home: Scaffold(
                  body: Builder(
                    builder: (context) => TextButton(
                      onPressed: () async {
                        if (date) {
                          await showSettloDatePicker(
                            context: context,
                            initialDate: DateTime(2026, 11, 10),
                            firstDate: DateTime(2026),
                            lastDate: DateTime(2027),
                          );
                        } else {
                          await showSettloPicker<int>(
                            context: context,
                            values: const [1, 2, 3, 4, 5],
                            selected: 3,
                            label: (value) => 'Day $value',
                          );
                        }
                      },
                      child: const Text('Open'),
                    ),
                  ),
                ),
              ),
            ),
          );
          await tester.tap(find.text('Open'));
          await tester.pumpAndSettle();
          expect(
            find.byType(CupertinoPickerDefaultSelectionOverlay),
            findsNWidgets(date ? 3 : 1),
          );
          await expectLater(
            find.byKey(settloGoldenSurfaceKey),
            matchesGoldenFile('goldens/$name.png'),
          );
        });
      }
    }
  }
}
