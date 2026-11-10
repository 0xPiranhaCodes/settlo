import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
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
                        for (var i = 0; i < 12; i++)
                          SizedBox(
                            height: 440,
                            child: Row(
                              children: [
                                Expanded(
                                  child: Theme(
                                    data: SettloTheme.dark(),
                                    child: SCard(
                                      hero: true,
                                      child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          Text(
                                            'NET POSITION',
                                            style: SettloTypography.footnote(
                                              color: SettloColors
                                                  .dark
                                                  .textSecondary,
                                            ),
                                          ),
                                          const SizedBox(height: 24),
                                          const MoneyText(
                                            Paise(67420000),
                                            size: 28,
                                          ),
                                          const SizedBox(height: 24),
                                          Text(
                                            'Across 2 spaces',
                                            style: SettloTypography.subheadline(
                                              color: SettloColors
                                                  .dark
                                                  .textSecondary,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ),
                                ),
                                Expanded(
                                  child: Theme(
                                    data: SettloTheme.light(),
                                    child: SCard(
                                      child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          Text(
                                            'Flat 402',
                                            style: SettloTypography.headline(
                                              color: SettloColors
                                                  .light
                                                  .textPrimary,
                                            ),
                                          ),
                                          const SizedBox(height: 24),
                                          const MoneyText(
                                            Paise(285000),
                                            tone: MoneyTone.owedToYou,
                                          ),
                                          const SizedBox(height: 24),
                                          Text(
                                            'Rahul paid',
                                            style: SettloTypography.subheadline(
                                              color: SettloColors
                                                  .light
                                                  .textSecondary,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ),
                                ),
                              ],
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
          if (!highContrast) {
            await tester.runAsync(() async {
              final boundary = tester.renderObject<RenderRepaintBoundary>(
                find.byKey(settloGoldenSurfaceKey),
              );
              final rect = tester.getRect(find.byType(SGlassTabBar));
              final image = await boundary.toImage();
              final data = (await image.toByteData())!;
              final samples = <int>[];
              final y = (rect.bottom - 4).round();
              for (var x = (rect.left + 20).round(); x < rect.right - 20; x++) {
                final offset = (y * image.width + x) * 4;
                samples.add(
                  (data.getUint8(offset) +
                          data.getUint8(offset + 1) +
                          data.getUint8(offset + 2)) ~/
                      3,
                );
              }
              samples.sort();
              expect(
                samples.last - samples.first,
                greaterThanOrEqualTo(40),
                reason:
                    'Broad backdrop detail must remain visible '
                    'through glass padding',
              );
              image.dispose();
            });
          }
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
