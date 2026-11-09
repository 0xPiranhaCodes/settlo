import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:settlo_auth/settlo_auth.dart';
import 'package:settlo_core/settlo_core.dart';

import 'support/fake_session.dart';

void main() {
  for (final brightness in Brightness.values) {
    testWidgets('follows the system when it is ${brightness.name}', (
      tester,
    ) async {
      tester.platformDispatcher.platformBrightnessTestValue = brightness;
      addTearDown(tester.platformDispatcher.clearPlatformBrightnessTestValue);

      await tester.pumpWidget(fakeSessionApp(null));
      await tester.pumpAndSettle();

      final context = tester.element(find.byType(WelcomeScreen));
      expect(Theme.of(context).brightness, brightness);
      expect(
        SettloColors.of(context),
        brightness == Brightness.dark ? SettloColors.dark : SettloColors.light,
      );
    });
  }

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
