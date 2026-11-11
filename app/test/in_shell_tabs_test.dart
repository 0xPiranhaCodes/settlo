import 'dart:async';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:settlo/native_tab_bar.dart';
import 'package:settlo/router/router.dart';

import 'support/fake_home.dart';
import 'support/fake_session.dart';

/// Screens pushed inside the shell, so the tab bar stays over them (#174).
const _pushed = {
  '/home/profile': 0,
  '/spaces/s1': 1,
  '/spaces/s1/balances': 1,
  '/loans/l1': 2,
};
const _roots = ['/home', '/spaces', '/loans', '/activity'];

/// The native bar's platform view id; it grows from test to test.
late int _barId;

/// The production app on an iPhone 17 Pro sized iOS screen, at [location].
Future<GoRouter> _open(WidgetTester tester, String location) async {
  tester.view
    ..physicalSize = const Size(402, 874)
    ..devicePixelRatio = 1
    ..viewPadding = const FakeViewPadding(top: 62, bottom: 34)
    ..padding = const FakeViewPadding(top: 62, bottom: 34);
  addTearDown(tester.view.reset);
  tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
    SystemChannels.platform_views,
    (call) async {
      if (call.method == 'create') {
        _barId = (call.arguments as Map<Object?, Object?>)['id']! as int;
      }
      return null;
    },
  );
  await tester.pumpWidget(
    fakeSessionApp(fakeSession, home: FakeHomeRepository(homeMain)),
  );
  await tester.pumpAndSettle();
  final router = ProviderScope.containerOf(
    tester.element(find.byType(Router<Object>)),
  ).read(routerProvider)..go(location);
  await tester.pumpAndSettle();
  expect(router.state.matchedLocation, location);
  return router;
}

/// The centre of tab [index] on the native bar.
Offset _tab(WidgetTester tester, int index) {
  final bar = tester.getRect(find.byType(UiKitView));
  return Offset(bar.left + bar.width * (index + 0.5) / 4, bar.top + 24);
}

/// What the engine asks before UIKit may have a touch, under the hit-test
/// blocking policy AppDelegate registers: does it reach the platform view?
bool _reachesUiKit(WidgetTester tester, Offset position) {
  final result = HitTestResult();
  tester.binding.hitTestInView(result, position, tester.view.viewId);
  return result.path.any((entry) => entry.target is NativeHitTestTarget);
}

/// Delivers a tap on tab [index] as `NativeTabBar.swift` sends it.
Future<void> _nativeTap(WidgetTester tester, int index) async {
  await tester.binding.defaultBinaryMessenger.handlePlatformMessage(
    nativeTabBarChannel(_barId),
    const StandardMethodCodec().encodeMethodCall(MethodCall('tap', index)),
    (_) {},
  );
  await tester.pumpAndSettle();
}

void main() {
  final ios = TargetPlatformVariant.only(TargetPlatform.iOS);

  for (final MapEntry(key: location, value: owner) in _pushed.entries) {
    testWidgets('on iOS, every tab is tappable from $location', (tester) async {
      final router = await _open(tester, location);
      for (var i = 0; i < 4; i++) {
        expect(_reachesUiKit(tester, _tab(tester, i)), isTrue, reason: '$i');
      }

      for (var i = 0; i < 4; i++) {
        if (i == owner) continue;
        router.go(location);
        await tester.pumpAndSettle();
        await _nativeTap(tester, i);
        expect(router.state.matchedLocation, _roots[i]);
      }

      // The selected tab again goes back to the tab's own screen.
      router.go(location);
      await tester.pumpAndSettle();
      await _nativeTap(tester, owner);
      expect(router.state.matchedLocation, _roots[owner]);
    }, variant: ios);

    testWidgets('on iOS, the last item on $location scrolls clear of the bar', (
      tester,
    ) async {
      await _open(tester, location);
      await tester.fling(
        find.byType(CustomScrollView).last,
        const Offset(0, -10000),
        10000,
      );
      await tester.pumpAndSettle();

      final barTop = tester.getRect(find.byType(UiKitView)).top;
      final viewport = tester.getRect(find.byType(CustomScrollView).last);
      final lowest = find
          .descendant(
            of: find.byType(CustomScrollView).last,
            matching: find.byType(Text),
          )
          .evaluate()
          .map((e) => e.renderObject! as RenderBox)
          .map((box) => box.localToGlobal(Offset.zero) & box.size)
          .where((rect) => rect.top < viewport.bottom)
          .map((rect) => rect.bottom)
          .reduce((a, b) => a > b ? a : b);
      expect(lowest, lessThanOrEqualTo(barTop));
    }, variant: ios);
  }

  testWidgets('on iOS, a dialog over Profile keeps the bar from UIKit', (
    tester,
  ) async {
    await _open(tester, '/home/profile');
    final context = tester.element(find.text('Delete account'));
    unawaited(
      showDialog<void>(context: context, builder: (_) => const Text('modal')),
    );
    await tester.pumpAndSettle();

    expect(_reachesUiKit(tester, _tab(tester, 1)), isFalse);
  }, variant: ios);
}
