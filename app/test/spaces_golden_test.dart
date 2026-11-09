import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:settlo/shell.dart';
import 'package:settlo_core/settlo_core.dart';
import 'package:settlo_spaces/settlo_spaces.dart';
import 'package:settlo_test_support/golden.dart';

import 'support/fake_space_ledger.dart';
import 'support/fake_spaces.dart';

/// [screen] in the shell's Spaces tab with [spaces] already loaded; see
/// `homeInShell` for why the data is loaded before the first frame.
Future<Widget> spacesInShell(
  List<SpaceSummary> spaces,
  Widget screen, {
  Map<String, SpaceLedger>? ledgers,
}) async {
  final container = ProviderContainer(
    overrides: [
      spacesRepositoryProvider.overrideWithValue(FakeSpacesRepository(spaces)),
      spaceLedgerRepositoryProvider.overrideWithValue(
        FakeSpaceLedgerRepository(ledgers),
      ),
    ],
  );
  addTearDown(container.dispose);
  await container.read(spacesProvider.future);
  for (final s in spaces) {
    await container.read(spaceLedgerProvider(s.id).future);
  }
  return UncontrolledProviderScope(
    container: container,
    child: SettloShell(currentIndex: 1, onTabSelected: (_) {}, child: screen),
  );
}

/// SpacesList and both tabs of Flat 402 in dark and light, and Space ·
/// empty in dark, against their artboards; and Flat 402's expenses with
/// pending settle-ups (#78) in dark.
void main() {
  final states = [
    ('list', spacesList, const SpacesListScreen(), ['dark', 'light']),
    (
      'empty',
      [spaceEmpty],
      SpaceExpensesScreen(spaceId: spaceEmpty.id),
      ['dark'],
    ),
    (
      'expenses',
      spacesList,
      SpaceExpensesScreen(spaceId: spacesList.first.id),
      ['dark', 'light'],
    ),
    (
      'balances',
      spacesList,
      SpaceScreen(spaceId: spacesList.first.id),
      ['dark', 'light'],
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

  for (final device in SettloGoldenDevices.all) {
    testWidgets('${device.name} dark spaces settle-ups golden', (tester) async {
      await pumpSettloGolden(
        tester,
        device: device,
        theme: SettloTheme.dark(),
        child: await spacesInShell(
          spacesList,
          SpaceExpensesScreen(spaceId: spacesList.first.id),
          ledgers: {'s1': flatLedgerWithSettleUp},
        ),
      );

      await expectLater(
        find.byKey(settloGoldenSurfaceKey),
        matchesGoldenFile('goldens/spaces_settle_ups_${device.name}_dark.png'),
      );
    });
  }
}
