import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:settlo/shell.dart';
import 'package:settlo_activity/settlo_activity.dart';
import 'package:settlo_core/settlo_core.dart';
import 'package:settlo_test_support/golden.dart';

import 'support/fake_activity.dart';
import 'support/fake_session.dart';
import 'support/fake_spaces.dart';

/// Rahul's wifi edit, questioned by Priya; you can still ask too.
final List<ActivityEntry> _questioned = [
  for (final e in activityFeed)
    if (e.action == ActivityAction.edited)
      ActivityEntry(
        id: e.id,
        at: e.at,
        kind: e.kind,
        action: e.action,
        byYou: e.byYou,
        actor: e.actor,
        spaceId: e.spaceId,
        spaceName: e.spaceName,
        description: e.description,
        amount: e.amount,
        beforeDescription: e.beforeDescription,
        beforeAmount: e.beforeAmount,
        questions: const [
          (byYou: false, name: 'Priya', note: 'Did the plan change?', at: null),
        ],
      )
    else
      e,
];

/// The Activity artboard (n30) in the shell on 9 Nov, dark and light:
/// Arjun's repayment waits for you on top, then the feed, with a chip for
/// each space and Loans. The `new` goldens (#109) are the same feed opened
/// after two entries arrived, counted on the bell, then narrowed to Flat
/// 402, with a member's question under Rahul's edit.
void main() {
  for (final device in SettloGoldenDevices.accessible) {
    for (final (name, theme, activity) in [
      ('dark', SettloTheme.dark(), FakeActivityRepository.new),
      ('light', SettloTheme.light(), FakeActivityRepository.new),
      // Narrowed to Flat 402, so the question is on screen.
      for (final (themeName, theme) in [
        ('dark', SettloTheme.dark()),
        ('light', SettloTheme.light()),
      ])
        (
          'new_$themeName',
          theme,
          () => FakeActivityRepository(
            entries: _questioned,
            seenAt: DateTime(2026, 11, 3, 22),
          ),
        ),
    ]) {
      testWidgets('${device.name} $name activity golden', (tester) async {
        final container = ProviderContainer(
          overrides: [
            sessionProvider.overrideWith(
              () => FakeSessionNotifier(fakeSession),
            ),
            activityRepositoryProvider.overrideWithValue(activity()),
            spacesRepositoryProvider.overrideWithValue(
              FakeSpacesRepository(spacesList),
            ),
            activityNowProvider.overrideWithValue(DateTime(2026, 11, 9, 18)),
          ],
        );
        addTearDown(container.dispose);
        container
          ..listen(needsYouProvider, (_, _) {})
          ..listen(activityFeedProvider, (_, _) {})
          ..listen(activitySpacesProvider, (_, _) {});
        await container.read(needsYouProvider.future);
        await container.read(activityFeedProvider.future);
        await container.read(activitySpacesProvider.future);

        await pumpSettloGolden(
          tester,
          device: device,
          theme: theme,
          act: (tester) async {
            if (name.startsWith('new')) await tester.tap(find.text('Flat 402'));
          },
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
          matchesGoldenFile('goldens/activity_${device.name}_$name.png'),
        );
      });
    }
  }
}
