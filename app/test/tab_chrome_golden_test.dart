import 'package:flutter/cupertino.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:settlo/native_tab_bar.dart';
import 'package:settlo/shell.dart';
import 'package:settlo_activity/settlo_activity.dart';
import 'package:settlo_core/settlo_core.dart';
import 'package:settlo_loans/settlo_loans.dart';
import 'package:settlo_spaces/settlo_spaces.dart';
import 'package:settlo_test_support/golden.dart';

import 'home_golden_test.dart' show homeInShell;
import 'spaces_golden_test.dart' show spacesInShell;
import 'support/fake_activity.dart';
import 'support/fake_home.dart';
import 'support/fake_loans.dart';
import 'support/fake_session.dart';
import 'support/fake_spaces.dart';

Future<Widget> _feed(bool loans) async {
  final container = ProviderContainer(
    overrides: [
      accountNameProvider.overrideWithValue(homeMain.name),
      sessionProvider.overrideWith(() => FakeSessionNotifier(fakeSession)),
      loansRepositoryProvider.overrideWithValue(
        FakeLoansRepository(loansList()),
      ),
      activityRepositoryProvider.overrideWithValue(FakeActivityRepository()),
      spacesRepositoryProvider.overrideWithValue(
        FakeSpacesRepository(spacesList),
      ),
      activityNowProvider.overrideWithValue(DateTime(2026, 11, 9, 18)),
    ],
  );
  addTearDown(container.dispose);
  if (loans) {
    container.listen(loansProvider, (_, _) {});
    await container.read(loansProvider.future);
  } else {
    container
      ..listen(needsYouProvider, (_, _) {})
      ..listen(activityFeedProvider, (_, _) {})
      ..listen(activitySpacesProvider, (_, _) {});
    await container.read(needsYouProvider.future);
    await container.read(activityFeedProvider.future);
    await container.read(activitySpacesProvider.future);
  }
  return UncontrolledProviderScope(
    container: container,
    child: SettloShell(
      currentIndex: loans ? 2 : 3,
      onTabSelected: (_) {},
      child: loans ? const LoanScreen() : const ActivityScreen(),
    ),
  );
}

void main() {
  for (final device in [
    SettloGoldenDevices.canvas390,
    const GoldenDevice(name: '375x667', size: Size(375, 667)),
    const GoldenDevice(
      name: '375x667_text200',
      size: Size(375, 667),
      textScale: 2,
    ),
  ]) {
    for (final dark in [false, true]) {
      for (final tab in ['home', 'spaces', 'loans', 'activity']) {
        testWidgets('tab chrome $tab ${device.name} $dark', (tester) async {
          final messenger = tester.binding.defaultBinaryMessenger;
          messenger.setMockMethodCallHandler(SystemChannels.platform_views, (
            call,
          ) async {
            if (call.method == 'create') {
              final id =
                  (call.arguments as Map<Object?, Object?>)['id']! as int;
              messenger.setMockMethodCallHandler(
                MethodChannel(nativeTabBarChannel(id)),
                (_) async => null,
              );
            }
            return null;
          });
          addTearDown(() async {
            await tester.pumpWidget(const SizedBox());
            messenger.setMockMethodCallHandler(
              SystemChannels.platform_views,
              null,
            );
          });
          final child = switch (tab) {
            'home' => await homeInShell(homeMain),
            'spaces' => await spacesInShell(
              spacesList,
              const SpacesListScreen(),
              accountName: homeMain.name,
            ),
            _ => await _feed(tab == 'loans'),
          };
          await pumpSettloGolden(
            tester,
            device: device,
            theme: (dark ? SettloTheme.dark() : SettloTheme.light()).copyWith(
              platform: TargetPlatform.iOS,
            ),
            child: child,
          );
          final firstContent = switch (tab) {
            'spaces' || 'activity' => find.byType(SSearchField),
            _ => find.byType(SGroup).first,
          };
          expect(
            tester.getTopLeft(firstContent).dy,
            tester
                    .getBottomLeft(
                      find.byKey(const ValueKey('tab-header-material')),
                    )
                    .dy +
                SettloTabScaffold.inset,
            reason: 'Every tab starts content at the shared title inset',
          );
          await expectLater(
            find.byKey(settloGoldenSurfaceKey),
            matchesGoldenFile(
              'goldens/tab_${tab}_${device.name}_${dark ? 'dark' : 'light'}.png',
            ),
          );
        });
      }
    }
  }
}
