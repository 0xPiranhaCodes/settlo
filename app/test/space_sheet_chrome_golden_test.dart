import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:settlo_core/settlo_core.dart';
import 'package:settlo_spaces/settlo_spaces.dart';
import 'package:settlo_test_support/golden.dart';

import 'spaces_golden_test.dart' show spacesInShell;
import 'support/fake_activity.dart';
import 'support/fake_spaces.dart';

void main() {
  for (final device in [
    SettloGoldenDevices.canvas390,
    const GoldenDevice(name: 'se375x667', size: Size(375, 667)),
    const GoldenDevice(
      name: 'se375x667_text200',
      size: Size(375, 667),
      textScale: 2,
    ),
  ]) {
    for (final dark in [false, true]) {
      for (final segment in ['expenses', 'balances', 'activity']) {
        testWidgets('sheet ${device.name} dark=$dark segment=$segment', (
          tester,
        ) async {
          await pumpSettloGolden(
            tester,
            device: device,
            theme: dark ? SettloTheme.dark() : SettloTheme.light(),
            child: await spacesInShell(
              spacesList,
              switch (segment) {
                'balances' => SpaceScreen(spaceId: spacesList.first.id),
                'activity' => SpaceActivityScreen(spaceId: spacesList.first.id),
                _ => SpaceExpensesScreen(spaceId: spacesList.first.id),
              },
              activity: segment == 'activity' ? FakeActivityRepository() : null,
            ),
          );
          expect(find.byType(SSheetHeader), findsOneWidget);
          expect(tester.takeException(), isNull);
          await expectLater(
            find.byKey(settloGoldenSurfaceKey),
            matchesGoldenFile(
              'goldens/sheet_space_${segment}_${device.name}_${dark ? 'dark' : 'light'}.png',
            ),
          );
          await tester.drag(
            find.byType(CustomScrollView),
            const Offset(0, -400),
          );
          await tester.pumpAndSettle();
          expect(tester.takeException(), isNull);
        });
      }
    }
  }
}
