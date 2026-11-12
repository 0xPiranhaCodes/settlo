import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:settlo/native_tab_bar.dart';
import 'package:settlo/shell.dart';
import 'package:settlo_activity/settlo_activity.dart';
import 'package:settlo_balances/settlo_balances.dart';
import 'package:settlo_core/settlo_core.dart';
import 'package:settlo_core/supabase/reminders.dart';
import 'package:settlo_profile/settlo_profile.dart';
import 'package:settlo_test_support/golden.dart';

import 'support/fake_activity.dart';
import 'support/fake_home.dart';
import 'support/fake_profile.dart';
import 'support/fake_reminders.dart';

/// Profile's sheet over Home in the shell, as the router stacks them (#196).
Future<Widget> _profileOverHome(ThemeMode mode) async {
  final container = ProviderContainer(
    overrides: [
      homeRepositoryProvider.overrideWithValue(FakeHomeRepository(homeMain)),
      activityRepositoryProvider.overrideWithValue(FakeActivityRepository()),
      reminderRepositoryProvider.overrideWithValue(FakeReminders()),
      profileRepositoryProvider.overrideWithValue(FakeProfileRepository()),
      themeModeRepositoryProvider.overrideWithValue(
        FakeThemeModeRepository(mode),
      ),
    ],
  );
  addTearDown(container.dispose);
  await Future.wait([
    container.read(homeProvider.future),
    container.read(activityFeedProvider.future),
    container.read(profileProvider.future),
    container.read(themeModeProvider.future),
  ]);
  return UncontrolledProviderScope(
    container: container,
    child: Navigator(
      pages: [
        MaterialPage<void>(
          child: SettloShell(
            currentIndex: 0,
            onTabSelected: (_) {},
            child: const HomeScreen(),
          ),
        ),
        const SettloNavigatorSheetPage<void>(child: ProfileScreen()),
      ],
      onDidRemovePage: (_) {},
    ),
  );
}

void main() {
  for (final platform in [TargetPlatform.android, TargetPlatform.iOS]) {
    final suffix = platform == TargetPlatform.iOS ? '_ios' : '';
    for (final device in SettloGoldenDevices.accessible) {
      for (final mode in [ThemeMode.dark, ThemeMode.light]) {
        for (final scrolled in [false, true]) {
          final state = scrolled ? '_scrolled' : '';
          final name = 'profile$suffix${state}_${device.name}_${mode.name}';
          testWidgets('$name golden', (tester) async {
            // iOS's tab bar is a UIKit view, which draws nothing here.
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
            final theme = mode == ThemeMode.dark
                ? SettloTheme.dark()
                : SettloTheme.light();
            await pumpSettloGolden(
              tester,
              device: device,
              theme: theme.copyWith(platform: platform),
              child: await _profileOverHome(mode),
              act: scrolled
                  ? (tester) => tester.drag(
                      find.byType(CustomScrollView).last,
                      const Offset(0, -300),
                    )
                  : null,
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
}
