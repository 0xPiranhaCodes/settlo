import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:settlo/router/router.dart';
import 'package:settlo/shell.dart';
import 'package:settlo_activity/settlo_activity.dart';
import 'package:settlo_core/settlo_core.dart';
import 'package:settlo_test_support/golden.dart';

import 'support/fake_activity.dart';
import 'support/fake_session.dart';

void main() {
  testWidgets(
    'Activity segment keeps the space route and filters all rows',
    (tester) async {
      await loadSettloFonts();
      tester.view
        ..physicalSize = const Size(390, 844)
        ..devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform_views,
        (_) async => null,
      );
      final activity = FakeActivityRepository(
        pending: [rahulSettleUpAnswer, arjunRepaymentAnswer],
        seenAt: DateTime(2026),
      );
      await tester.pumpWidget(fakeSessionApp(fakeSession, activity: activity));
      await tester.pumpAndSettle();
      final container = ProviderScope.containerOf(
        tester.element(find.byType(Router<Object>)),
      );
      final router = container.read(routerProvider)..go('/spaces/s1');
      await tester.pumpAndSettle();
      await tester.tap(find.text('Activity').first);
      await tester.pumpAndSettle();
      expect(router.state.uri.path, '/spaces/s1/activity');
      expect(
        tester.widget<SettloShell>(find.byType(SettloShell)).currentIndex,
        1,
      );
      expect(find.text('Flat 402'), findsWidgets);
      expect(find.text('Expenses'), findsOneWidget);
      expect(find.text('Balances'), findsOneWidget);
      expect(find.text('Priya added Electricity'), findsOneWidget);
      expect(find.text('Rahul recorded a ₹300 settle-up'), findsOneWidget);
      expect(find.text('Kabir settled with you'), findsNothing);
      expect(find.text('Arjun repaid · you confirmed'), findsNothing);
      expect(find.text('Arjun recorded a ₹25,000 repayment'), findsNothing);
      expect(find.text('All'), findsNothing);
      expect(activity.calls, contains('feed 30 null s1'));
      expect(activity.calls, isNot(contains('markSeen')));
      expect(container.read(activityFilterProvider), allActivity);

      await tester.tap(find.text('Balances'));
      await tester.pumpAndSettle();
      expect(router.state.uri.path, '/spaces/s1/balances');
      await tester.tap(find.text('Activity').first);
      await tester.pumpAndSettle();
      expect(router.state.uri.path, '/spaces/s1/activity');
      router.pop();
      await tester.pumpAndSettle();
      expect(router.state.uri.path, '/spaces');

      router.go('/spaces/s2/activity');
      await tester.pumpAndSettle();
      expect(find.text('Kabir settled with you'), findsOneWidget);
      expect(find.text('Priya added Electricity'), findsNothing);
      expect(find.text('Rahul recorded a ₹300 settle-up'), findsNothing);

      router.go('/activity');
      await tester.pumpAndSettle();
      expect(find.text('All'), findsOneWidget);
      expect(find.text('Priya added Electricity'), findsOneWidget);
      expect(find.text('Arjun recorded a ₹25,000 repayment'), findsOneWidget);
      expect(container.read(activityFilterProvider), allActivity);
    },
    variant: const TargetPlatformVariant({
      TargetPlatform.android,
      TargetPlatform.iOS,
    }),
  );
}
