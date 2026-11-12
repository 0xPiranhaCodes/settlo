import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:settlo/native_tab_bar.dart';
import 'package:settlo_core/settlo_core.dart';
import 'package:settlo_spaces/settlo_spaces.dart';
import 'package:settlo_test_support/golden.dart';

import 'home_golden_test.dart' show homeInShell;
import 'spaces_golden_test.dart' show spacesInShell;
import 'support/fake_home.dart';
import 'support/fake_spaces.dart';

/// iOS 26's header (#191): soft scroll edge, no status strip, band, plate
/// or hairline. The glass buttons, mark and tab bar are UIKit views, which
/// draw nothing in a widget test; the simulator captures in the PR show them.
void main() {
  tearDown(() => iosMajorVersion = 0);

  for (final (name, screen) in [
    ('home', () => homeInShell(homeMain)),
    (
      'space',
      () => spacesInShell(
        spacesList,
        SpaceExpensesScreen(spaceId: spacesList.first.id),
      ),
    ),
  ]) {
    for (final themeName in ['dark', 'light']) {
      for (final scrolled in [false, true]) {
        final state = scrolled ? 'scrolled' : 'rest';
        testWidgets('ios26 $name $themeName $state golden', (tester) async {
          iosMajorVersion = 26;
          final messenger = tester.binding.defaultBinaryMessenger;
          messenger.setMockMethodCallHandler(SystemChannels.platform_views, (
            call,
          ) async {
            if (call.method == 'create') {
              final id =
                  (call.arguments as Map<Object?, Object?>)['id']! as int;
              for (final channel in [
                nativeTabBarChannel(id),
                glassActionChannel(id),
              ]) {
                messenger.setMockMethodCallHandler(
                  MethodChannel(channel),
                  (_) async => null,
                );
              }
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
          final theme = themeName == 'dark'
              ? SettloTheme.dark()
              : SettloTheme.light();
          await pumpSettloGolden(
            tester,
            device: SettloGoldenDevices.canvas390,
            theme: theme.copyWith(platform: TargetPlatform.iOS),
            child: await screen(),
            act: scrolled
                ? (tester) => tester.drag(
                    find.byType(CustomScrollView).first,
                    const Offset(0, -260),
                  )
                : null,
          );
          await expectLater(
            find.byKey(settloGoldenSurfaceKey),
            matchesGoldenFile('goldens/ios26_${name}_${themeName}_$state.png'),
          );
        });
      }
    }
  }
}
