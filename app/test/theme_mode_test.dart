import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:settlo_auth/settlo_auth.dart';
import 'package:settlo_core/settlo_core.dart';

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
  }
}
