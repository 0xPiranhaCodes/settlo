import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:settlo_auth/settlo_auth.dart';
import 'package:settlo_core/settlo_core.dart';
import 'package:settlo_profile/settlo_profile.dart';

import 'support/fake_session.dart';

void main() {
  for (final brightness in Brightness.values) {
    testWidgets('boots dark when the system is ${brightness.name}', (
      tester,
    ) async {
      tester.platformDispatcher.platformBrightnessTestValue = brightness;
      addTearDown(tester.platformDispatcher.clearPlatformBrightnessTestValue);

      await tester.pumpWidget(fakeSessionApp(null));
      await tester.pumpAndSettle();

      final context = tester.element(find.byType(WelcomeScreen));
      expect(Theme.of(context).brightness, Brightness.dark);
      expect(SettloColors.of(context), SettloColors.dark);
    });

    testWidgets('explicit system setting follows ${brightness.name}', (
      tester,
    ) async {
      tester.platformDispatcher.platformBrightnessTestValue = brightness;
      addTearDown(tester.platformDispatcher.clearPlatformBrightnessTestValue);

      await tester.pumpWidget(
        fakeSessionApp(null, themeMode: ThemeMode.system),
      );
      await tester.pumpAndSettle();

      final context = tester.element(find.byType(WelcomeScreen));
      expect(Theme.of(context).brightness, brightness);
    });
  }

  testWidgets('stays dark while the saved preference loads', (tester) async {
    tester.platformDispatcher.platformBrightnessTestValue = Brightness.light;
    addTearDown(tester.platformDispatcher.clearPlatformBrightnessTestValue);
    final repository = _DelayedThemeModeRepository();

    await tester.pumpWidget(
      fakeSessionApp(null, themeModeRepository: repository),
    );
    await tester.pump();

    var context = tester.element(find.byType(WelcomeScreen));
    expect(Theme.of(context).brightness, Brightness.dark);

    repository.complete(ThemeMode.system);
    await tester.pumpAndSettle();
    context = tester.element(find.byType(WelcomeScreen));
    expect(Theme.of(context).brightness, Brightness.light);
  });

  for (final (mode, expected) in [
    (ThemeMode.dark, Brightness.dark),
    (ThemeMode.light, Brightness.light),
  ]) {
    testWidgets('${mode.name} overrides the system', (tester) async {
      tester.platformDispatcher.platformBrightnessTestValue =
          expected == Brightness.dark ? Brightness.light : Brightness.dark;
      addTearDown(tester.platformDispatcher.clearPlatformBrightnessTestValue);

      await tester.pumpWidget(fakeSessionApp(null, themeMode: mode));
      await tester.pumpAndSettle();

      final context = tester.element(find.byType(WelcomeScreen));
      expect(Theme.of(context).brightness, expected);
    });
  }
}

final class _DelayedThemeModeRepository implements ThemeModeRepository {
  final _loaded = Completer<ThemeMode>();

  void complete(ThemeMode mode) => _loaded.complete(mode);

  @override
  Future<ThemeMode> load() => _loaded.future;

  @override
  Future<void> save(ThemeMode mode) async {}
}
