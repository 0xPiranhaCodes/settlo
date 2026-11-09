import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:settlo/shell.dart';
import 'package:settlo_core/settlo_core.dart';
import 'package:settlo_spaces/settlo_spaces.dart';
import 'package:settlo_test_support/golden.dart';

import 'support/fake_spaces.dart';

/// [screen] in the shell's Spaces tab with [spaces] already loaded; see
/// `homeInShell` for why the data is loaded before the first frame.
Future<Widget> spacesInShell(List<SpaceSummary> spaces, Widget screen) async {
  final container = ProviderContainer(
    overrides: [
      spacesRepositoryProvider.overrideWithValue(FakeSpacesRepository(spaces)),
    ],
  );
  addTearDown(container.dispose);
  await container.read(spacesProvider.future);
  return UncontrolledProviderScope(
    container: container,
    child: SettloShell(currentIndex: 1, onTabSelected: (_) {}, child: screen),
  );
}

/// SpacesList in dark and light, and Space · empty in dark, against their
/// artboards.
void main() {
  final states = [
    ('list', spacesList, const SpacesListScreen(), ['dark', 'light']),
    (
      'empty',
      [spaceEmpty],
      SpaceExpensesScreen(spaceId: spaceEmpty.id),
      ['dark'],
    ),
  ];
  for (final device in SettloGoldenDevices.all) {
    for (final (state, spaces, screen, themes) in states) {
      for (final themeName in themes) {
        testWidgets('${device.name} $themeName spaces $state golden', (
          tester,
        ) async {
          await pumpSettloGolden(
            tester,
            device: device,
            theme: themeName == 'dark'
                ? SettloTheme.dark()
                : SettloTheme.light(),
            child: await spacesInShell(spaces, screen),
          );

          await expectLater(
            find.byKey(settloGoldenSurfaceKey),
            matchesGoldenFile(
              'goldens/spaces_${state}_${device.name}_$themeName.png',
            ),
          );
        });
      }
    }
  }
}
