import 'dart:async';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:settlo/router/router.dart';

import 'support/fake_home.dart';
import 'support/fake_session.dart';

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

void main() {
  final ios = TargetPlatformVariant.only(TargetPlatform.iOS);
  for (final location in ['/spaces/s1', '/spaces/s1/balances', '/loans/l1']) {
    testWidgets('root sheet blocks every tab until closed: $location', (
      tester,
    ) async {
      final router = await _open(tester, location);
      for (var i = 0; i < 4; i++) {
        expect(_reachesUiKit(tester, _tab(tester, i)), isFalse);
      }
      await tester.tap(find.bySemanticsLabel('Close'));
      await tester.pumpAndSettle();
      expect(
        router.state.matchedLocation,
        location.startsWith('/loans') ? '/loans' : '/spaces',
      );
      for (var i = 0; i < 4; i++) {
        expect(_reachesUiKit(tester, _tab(tester, i)), isTrue);
      }
    }, variant: ios);
  }

  for (final origin in ['/home', '/spaces', '/activity']) {
    testWidgets('loan sheet returns to $origin', (tester) async {
      final router = await _open(tester, origin);
      unawaited(router.push('/loans/l1'));
      await tester.pumpAndSettle();
      for (var i = 0; i < 4; i++) {
        expect(_reachesUiKit(tester, _tab(tester, i)), isFalse);
      }
      await tester.tap(find.bySemanticsLabel('Close'));
      await tester.pumpAndSettle();
      expect(router.state.matchedLocation, origin);
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
