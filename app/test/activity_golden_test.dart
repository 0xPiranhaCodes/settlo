import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:settlo/shell.dart';
import 'package:settlo_activity/settlo_activity.dart';
import 'package:settlo_core/settlo_core.dart';
import 'package:settlo_test_support/golden.dart';

import 'support/fake_activity.dart';

/// The Activity artboard (n30) in the shell on 9 Nov, dark and light:
/// Arjun's repayment waits for you on top, then the feed.
void main() {
  for (final device in SettloGoldenDevices.all) {
    for (final (themeName, theme) in [
      ('dark', SettloTheme.dark()),
      ('light', SettloTheme.light()),
    ]) {
      testWidgets('${device.name} $themeName activity golden', (tester) async {
        final container = ProviderContainer(
          overrides: [
            activityRepositoryProvider.overrideWithValue(
              FakeActivityRepository(),
            ),
            activityNowProvider.overrideWithValue(DateTime(2026, 11, 9, 18)),
          ],
        );
        addTearDown(container.dispose);
        container
          ..listen(needsYouProvider, (_, _) {})
          ..listen(activityFeedProvider, (_, _) {});
        await container.read(needsYouProvider.future);
        await container.read(activityFeedProvider.future);

        await pumpSettloGolden(
          tester,
          device: device,
          theme: theme,
          child: UncontrolledProviderScope(
            container: container,
            child: SettloShell(
              currentIndex: 3,
              onTabSelected: (_) {},
              child: const ActivityScreen(),
            ),
          ),
        );

        await expectLater(
          find.byKey(settloGoldenSurfaceKey),
          matchesGoldenFile('goldens/activity_${device.name}_$themeName.png'),
        );
      });
    }
  }
}
