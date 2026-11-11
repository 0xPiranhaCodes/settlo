import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:settlo/shell.dart';
import 'package:settlo_core/settlo_core.dart';
import 'package:settlo_core/supabase/reminders.dart';
import 'package:settlo_profile/settlo_profile.dart';
import 'package:settlo_test_support/golden.dart';

import 'support/fake_profile.dart';
import 'support/fake_reminders.dart';

Future<Widget> _profileInShell(ThemeMode mode) async {
  final container = ProviderContainer(
    overrides: [
      reminderRepositoryProvider.overrideWithValue(FakeReminders()),
      profileRepositoryProvider.overrideWithValue(FakeProfileRepository()),
      themeModeRepositoryProvider.overrideWithValue(
        FakeThemeModeRepository(mode),
      ),
    ],
  );
  addTearDown(container.dispose);
  await Future.wait([
    container.read(profileProvider.future),
    container.read(themeModeProvider.future),
  ]);
  return UncontrolledProviderScope(
    container: container,
    child: SettloShell(
      currentIndex: 0,
      onTabSelected: (_) {},
      child: const ProfileScreen(),
    ),
  );
}

void main() {
  for (final device in SettloGoldenDevices.accessible) {
    for (final mode in [ThemeMode.dark, ThemeMode.light]) {
      testWidgets('${device.name} ${mode.name} profile golden', (tester) async {
        await pumpSettloGolden(
          tester,
          device: device,
          theme: mode == ThemeMode.dark
              ? SettloTheme.dark()
              : SettloTheme.light(),
          child: await _profileInShell(mode),
        );

        await expectLater(
          find.byKey(settloGoldenSurfaceKey),
          matchesGoldenFile('goldens/profile_${device.name}_${mode.name}.png'),
        );
      });
    }
  }
}
