import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:settlo/shell.dart';
import 'package:settlo_balances/settlo_balances.dart';
import 'package:settlo_core/settlo_core.dart';

import 'support/fake_home.dart';
import 'support/golden.dart';

/// Home in the shell with [data] already loaded. Riverpod pauses widgets
/// under a disabled [TickerMode], as the golden harness sets, so the data
/// is loaded before the first frame rather than awaited after it.
Future<Widget> homeInShell(HomeData data) async {
  final container = ProviderContainer(
    overrides: [
      homeRepositoryProvider.overrideWithValue(FakeHomeRepository(data)),
    ],
  );
  addTearDown(container.dispose);
  await container.read(homeProvider.future);
  return UncontrolledProviderScope(
    container: container,
    child: SettloShell(
      currentIndex: 0,
      onTabSelected: (_) {},
      child: const HomeScreen(),
    ),
  );
}

/// Each Home state against its artboard: Main, HomeEmpty and HomeFound in
/// dark, and Main in light against HomeLight (the theme switch is not
/// built yet, so light is forced here).
void main() {
  final states = [
    ('main', homeMain, ['dark', 'light']),
    ('empty', homeEmpty, ['dark']),
    ('found', homeFound, ['dark']),
  ];
  for (final device in SettloGoldenDevices.all) {
    for (final (state, data, themes) in states) {
      for (final themeName in themes) {
        testWidgets('${device.name} $themeName home $state golden', (
          tester,
        ) async {
          await pumpSettloGolden(
            tester,
            device: device,
            theme: themeName == 'dark'
                ? SettloTheme.dark()
                : SettloTheme.light(),
            child: await homeInShell(data),
          );

          await expectLater(
            find.byKey(settloGoldenSurfaceKey),
            matchesGoldenFile(
              'goldens/home_${state}_${device.name}_$themeName.png',
            ),
          );
        });
      }
    }
  }
}
