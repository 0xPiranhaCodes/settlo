import 'package:flutter_test/flutter_test.dart';
import 'package:settlo/shell.dart';
import 'package:settlo_activity/settlo_activity.dart';
import 'package:settlo_core/settlo_core.dart';
import 'package:settlo_loans/settlo_loans.dart';

import 'package:settlo_test_support/golden.dart';

void main() {
  // Home and Spaces are covered by their own golden tests, with data faked.
  const tabs = [('loans', LoanScreen()), ('activity', ActivityScreen())];
  for (final device in SettloGoldenDevices.all) {
    for (final (themeName, theme) in [
      ('dark', SettloTheme.dark()),
      ('light', SettloTheme.light()),
    ]) {
      for (final (i, (tab, screen)) in tabs.indexed) {
        testWidgets('${device.name} $themeName $tab shell golden', (
          tester,
        ) async {
          await pumpSettloGolden(
            tester,
            device: device,
            theme: theme,
            child: SettloShell(
              currentIndex: i + 2,
              onTabSelected: (_) {},
              child: screen,
            ),
          );

          await expectLater(
            find.byKey(settloGoldenSurfaceKey),
            matchesGoldenFile(
              'goldens/shell_${tab}_${device.name}_$themeName.png',
            ),
          );
        });
      }
    }
  }
}
