import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:settlo/shell.dart';
import 'package:settlo_core/settlo_core.dart';
import 'package:settlo_test_support/golden.dart';

void main() {
  for (final device in SettloGoldenDevices.accessible) {
    for (final (themeName, theme) in [
      ('dark', SettloTheme.dark()),
      ('light', SettloTheme.light()),
    ]) {
      for (final highContrast in [false, true]) {
        testWidgets('glass scrolled ${device.name} $themeName $highContrast', (
          tester,
        ) async {
          await pumpSettloGolden(
            tester,
            device: device,
            theme: theme,
            child: Builder(
              builder: (context) => MediaQuery(
                data: MediaQuery.of(context)
                    .copyWith(highContrast: highContrast),
                child: SettloShell(
                  currentIndex: 2,
                  onTabSelected: (_) {},
                  child: Builder(
                    builder: (context) => ListView(
                      padding: EdgeInsets.only(
                        bottom: MediaQuery.paddingOf(context).bottom,
                      ),
                      children: [
                        for (var i = 0; i < 24; i++)
                          Container(
                            height: 80,
                            color: i.isEven
                                ? SettloColors.light.surface
                                : SettloColors.dark.surface,
                            padding: const EdgeInsets.all(20),
                            child: Text(
                              'Scrolling content · $i',
                              style: TextStyle(
                                color: i.isEven
                                    ? SettloColors.light.textPrimary
                                    : SettloColors.dark.textPrimary,
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
            act: (tester) async {
              await tester.drag(find.byType(ListView), const Offset(0, -465));
            },
          );
          await expectLater(
            find.byKey(settloGoldenSurfaceKey),
            matchesGoldenFile(
              'goldens/glass_scrolled_${device.name}_${themeName}_${highContrast ? 'solid' : 'blur'}.png',
            ),
          );
        });
      }
    }
  }
}
