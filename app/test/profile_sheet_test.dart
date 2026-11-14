import 'dart:async';

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:settlo/router/router.dart';
import 'package:settlo_balances/settlo_balances.dart';
import 'package:settlo_core/settlo_core.dart';
import 'package:settlo_profile/settlo_profile.dart';

import 'support/fake_home.dart';
import 'support/fake_session.dart';

/// The production app at [location], as a deep link delivers it.
Future<GoRouter> _open(WidgetTester tester, String location) async {
  tester.view
    ..physicalSize = const Size(402, 874)
    ..devicePixelRatio = 1
    ..viewPadding = const FakeViewPadding(top: 62, bottom: 34)
    ..padding = const FakeViewPadding(top: 62, bottom: 34);
  addTearDown(tester.view.reset);
  // The iOS tab bar is a UIKit view.
  tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
    SystemChannels.platform_views,
    (_) async => null,
  );
  await tester.pumpWidget(
    fakeSessionApp(fakeSession, home: FakeHomeRepository(homeMain)),
  );
  await tester.pumpAndSettle();
  final router = ProviderScope.containerOf(
    tester.element(find.byType(Router<Object>)),
  ).read(routerProvider)..go(location);
  await tester.pumpAndSettle();
  return router;
}

Route<Object?> _route(WidgetTester tester, Finder finder) =>
    ModalRoute.of(tester.element(finder))!;

/// The route Profile's sheet is, on the app's root navigator.
Route<Object?> _sheet(WidgetTester tester) {
  final nested = _route(tester, find.byType(ProfileScreen)).navigator!;
  return ModalRoute.of(nested.context)!;
}

void main() {
  for (final platform in [TargetPlatform.iOS, TargetPlatform.android]) {
    final variant = TargetPlatformVariant.only(platform);
    final ios = platform == TargetPlatform.iOS;

    testWidgets('a deep link opens Profile as a sheet over Home', (
      tester,
    ) async {
      final router = await _open(tester, SettloRoutes.profile);

      expect(router.state.matchedLocation, SettloRoutes.profile);
      expect(
        _sheet(tester),
        ios
            ? isA<CupertinoSheetRoute<void>>()
            : isA<ModalBottomSheetRoute<void>>(),
      );
      // Home stays mounted behind it.
      expect(find.byType(HomeScreen, skipOffstage: false), findsOne);
      expect(
        tester.getSemantics(find.bySemanticsLabel('Close')),
        // VoiceOver reads it as the Close button.
        isSemantics(label: 'Close', isButton: true, hasTapAction: true),
      );
    }, variant: variant);

    testWidgets('Close dismisses the sheet once, back to Home', (tester) async {
      final router = await _open(tester, SettloRoutes.profile);
      await tester.tap(
        find.descendant(
          of: find.byType(ProfileScreen),
          matching: find.byWidgetPredicate(
            (widget) => widget is SPressable && widget.label == 'Close',
          ),
        ),
      );
      await tester.tap(
        find.descendant(
          of: find.byType(ProfileScreen),
          matching: find.byWidgetPredicate(
            (widget) => widget is SPressable && widget.label == 'Close',
          ),
        ),
        warnIfMissed: false,
      );
      await tester.pumpAndSettle();

      expect(find.byType(ProfileScreen), findsNothing);
      expect(router.state.matchedLocation, SettloRoutes.home);
      expect(find.byType(HomeScreen), findsOne);
    }, variant: variant);

    testWidgets('Export pushes inside the sheet, and Back returns to it', (
      tester,
    ) async {
      final router = await _open(tester, SettloRoutes.profile);
      final sheet = _sheet(tester);
      await tester.ensureVisible(find.text('Export'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Export'));
      await tester.pumpAndSettle();

      expect(find.byType(ExportSheet), findsOne);
      expect(
        ModalRoute.of(
          _route(tester, find.byType(ExportSheet)).navigator!.context,
        ),
        sheet,
        reason: 'in the sheet, not over it',
      );

      // The system back pops the page, not the sheet.
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      expect(find.byType(ExportSheet), findsNothing);
      expect(find.byType(ProfileScreen), findsOne);
      expect(router.state.matchedLocation, SettloRoutes.profile);

      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      expect(find.byType(ProfileScreen), findsNothing);
      expect(router.state.matchedLocation, SettloRoutes.home);
    }, variant: variant);

    testWidgets('the other tabs keep their place under the sheet', (
      tester,
    ) async {
      final router = await _open(tester, SettloRoutes.space('s1'));
      router.go(SettloRoutes.profile);
      await tester.pumpAndSettle();
      await tester.tap(
        find.descendant(
          of: find.byType(ProfileScreen),
          matching: find.byWidgetPredicate(
            (widget) => widget is SPressable && widget.label == 'Close',
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(router.state.matchedLocation, SettloRoutes.home);

      tester
          .widget<StatefulNavigationShell>(find.byType(StatefulNavigationShell))
          .goBranch(1);
      await tester.pumpAndSettle();
      expect(router.state.matchedLocation, SettloRoutes.spaces);
    }, variant: variant);

    testWidgets('pushed from another tab, the sheet stays over that tab', (
      tester,
    ) async {
      final router = await _open(tester, SettloRoutes.space('s1'));
      StatefulNavigationShell shell() => tester.widget(
        find.byType(StatefulNavigationShell, skipOffstage: false),
      );
      unawaited(router.push<void>(SettloRoutes.profileSheet));
      await tester.pumpAndSettle();

      expect(_sheet(tester), isA<ModalRoute<void>>());
      expect(shell().currentIndex, 1, reason: 'Spaces stays selected');
      await tester.tap(
        find.descendant(
          of: find.byType(ProfileScreen),
          matching: find.byWidgetPredicate(
            (widget) => widget is SPressable && widget.label == 'Close',
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byType(ProfileScreen), findsNothing);
      expect(shell().currentIndex, 1);
      expect(router.state.matchedLocation, SettloRoutes.space('s1'));
      shell().goBranch(0);
      await tester.pumpAndSettle();
      expect(router.state.matchedLocation, SettloRoutes.home);
      shell().goBranch(1);
      await tester.pumpAndSettle();
      expect(router.state.matchedLocation, SettloRoutes.spaces);
    }, variant: variant);

    for (final (index, tab) in [
      (1, SettloRoutes.spaces),
      (2, SettloRoutes.loans),
      (3, SettloRoutes.activity),
    ]) {
      testWidgets('on $tab, the avatar opens the sheet over that tab', (
        tester,
      ) async {
        // Another tab's root remains selected after this sheet closes.
        final kept = index == 1 ? SettloRoutes.home : SettloRoutes.spaces;
        final router = await _open(tester, kept);
        StatefulNavigationShell shell() => tester.widget(
          find.byType(StatefulNavigationShell, skipOffstage: false),
        );
        shell().goBranch(index);
        await tester.pumpAndSettle();
        expect(router.state.matchedLocation, tab);

        await tester.tap(find.byTooltip('Profile'));
        await tester.pumpAndSettle();
        expect(_sheet(tester), isA<ModalRoute<void>>());
        expect(shell().currentIndex, index, reason: 'the tab stays selected');

        await tester.tap(
          find.byWidgetPredicate(
            (widget) => widget is SPressable && widget.label == 'Close',
          ),
        );
        await tester.pumpAndSettle();
        expect(find.byType(ProfileScreen), findsNothing);
        expect(shell().currentIndex, index);
        expect(router.state.matchedLocation, tab);

        shell().goBranch(index == 1 ? 0 : 1);
        await tester.pumpAndSettle();
        expect(router.state.matchedLocation, kept);
      }, variant: variant);
    }
  }

  testWidgets('on iOS, a swipe down with Export pushed closes the sheet', (
    tester,
  ) async {
    final router = await _open(tester, SettloRoutes.profile);
    await tester.ensureVisible(find.text('Export'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Export'));
    await tester.pumpAndSettle();
    expect(find.byType(ExportSheet), findsOne);

    await tester.flingFrom(const Offset(200, 160), const Offset(0, 600), 2000);
    await tester.pumpAndSettle();

    expect(find.byType(ExportSheet), findsNothing);
    expect(find.byType(ProfileScreen), findsNothing);
    expect(router.state.matchedLocation, SettloRoutes.home);
  }, variant: TargetPlatformVariant.only(TargetPlatform.iOS));

  testWidgets('on iOS, an edge swipe from Export returns to Profile', (
    tester,
  ) async {
    final router = await _open(tester, SettloRoutes.profile);
    await tester.ensureVisible(find.text('Export'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Export'));
    await tester.pumpAndSettle();

    await tester.flingFrom(const Offset(2, 400), const Offset(380, 0), 2000);
    await tester.pumpAndSettle();

    expect(find.byType(ExportSheet), findsNothing);
    expect(find.byType(ProfileScreen), findsOne);
    expect(router.state.matchedLocation, SettloRoutes.profile);
  }, variant: TargetPlatformVariant.only(TargetPlatform.iOS));

  testWidgets('on iOS, a swipe down dismisses the sheet', (tester) async {
    final router = await _open(tester, SettloRoutes.profile);
    await tester.flingFrom(const Offset(200, 160), const Offset(0, 600), 2000);
    await tester.pumpAndSettle();

    expect(find.byType(ProfileScreen), findsNothing);
    expect(router.state.matchedLocation, SettloRoutes.home);
    expect(find.byType(HomeScreen), findsOne);
  }, variant: TargetPlatformVariant.only(TargetPlatform.iOS));

  testWidgets('on Android, a drag down on the handle dismisses the sheet', (
    tester,
  ) async {
    final router = await _open(tester, SettloRoutes.profile);
    final handle = tester.getCenter(
      find.byWidgetPredicate((w) => w.runtimeType.toString() == '_DragHandle'),
    );
    await tester.flingFrom(handle, const Offset(0, 600), 2000);
    await tester.pumpAndSettle();

    expect(find.byType(ProfileScreen), findsNothing);
    expect(router.state.matchedLocation, SettloRoutes.home);
  }, variant: TargetPlatformVariant.only(TargetPlatform.android));
}
