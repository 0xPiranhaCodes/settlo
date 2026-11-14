import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:settlo/main.dart';
import 'package:settlo/router/router.dart';
import 'package:settlo_core/settlo_core.dart';
import 'package:settlo_loans/settlo_loans.dart';
import 'package:settlo_test_support/golden.dart';

import 'support/fake_home.dart';
import 'support/fake_session.dart';

void main() {
  for (final mode in [ThemeMode.light, ThemeMode.dark]) {
    testWidgets('closing a sheet restores the ${mode.name} status bar (#259)', (
      tester,
    ) async {
      await loadSettloFonts();
      tester.view
        ..physicalSize = SettloGoldenDevices.canvas390.size
        ..devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      // SettloApp builds its own theme, so the platform comes from here.
      debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
      try {
        await tester.pumpWidget(
          fakeSessionApp(
            fakeSession,
            themeMode: mode,
            home: FakeHomeRepository(homeMain),
          ),
        );
        await tester.pumpAndSettle();
        // Dark icons on the cream background, light ones in dark mode.
        final icons = mode == ThemeMode.light
            ? Brightness.dark
            : Brightness.light;
        expect(SystemChrome.latestStyle?.statusBarIconBrightness, icons);

        final router = ProviderScope.containerOf(
          tester.element(find.byType(SettloApp)),
        ).read(routerProvider);
        unawaited(router.push(SettloRoutes.newLoan));
        await tester.pumpAndSettle();
        expect(find.byType(NewLoanSheet), findsOne);
        // The sheet's dark gap above it asks for light icons.
        expect(
          SystemChrome.latestStyle?.statusBarIconBrightness,
          Brightness.light,
        );

        router.pop();
        await tester.pumpAndSettle();
        expect(find.byType(NewLoanSheet), findsNothing);
        expect(SystemChrome.latestStyle?.statusBarIconBrightness, icons);
      } finally {
        debugDefaultTargetPlatformOverride = null;
      }
    });
  }
}
