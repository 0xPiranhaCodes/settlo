import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:settlo_core/settlo_core.dart';
import 'package:settlo_settle/settlo_settle.dart';
import 'package:settlo_test_support/golden.dart';

import 'support/fake_expenses.dart';
import 'support/fake_settle.dart';
import 'support/fake_spaces.dart';

/// The Settle artboard (Priya pays you ₹2,100 in Flat 402, a request,
/// n22) and the SettlePay artboard (you pay Kabir ₹3,650 in Goa trip,
/// coral, n44).
void main() {
  for (final (name, screen) in [
    ('settle', const SettleScreen(spaceId: 's1', memberId: 'm3')),
    ('settle_pay', const SettlePayScreen(spaceId: 's2', memberId: 'm5')),
  ]) {
    for (final device in [
      ...SettloGoldenDevices.accessible,
      const GoldenDevice(name: 'se375x667', size: Size(375, 667)),
      const GoldenDevice(
        name: 'se375x667_text200',
        size: Size(375, 667),
        textScale: 2,
      ),
    ]) {
      for (final (themeName, theme) in [
        ('dark', SettloTheme.dark()),
        ('light', SettloTheme.light()),
      ]) {
        testWidgets('${device.name} $themeName $name golden', (tester) async {
          final container = ProviderContainer(
            overrides: [
              spacesRepositoryProvider.overrideWithValue(
                FakeSpacesRepository(settleSpaces()),
              ),
              expensesRepositoryProvider.overrideWithValue(
                FakeExpensesRepository(),
              ),
            ],
          );
          addTearDown(container.dispose);
          container.listen(settleSpacesProvider, (_, _) {});
          await container.read(settleSpacesProvider.future);

          await pumpSettloGolden(
            tester,
            device: device,
            theme: theme,
            child: UncontrolledProviderScope(
              container: container,
              child: ColoredBox(
                color: theme.scaffoldBackgroundColor,
                child: screen,
              ),
            ),
          );

          await expectLater(
            find.byKey(settloGoldenSurfaceKey),
            matchesGoldenFile('goldens/${name}_${device.name}_$themeName.png'),
          );
        });
      }
    }
  }
}
