import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:settlo_activity/settlo_activity.dart';
import 'package:settlo_core/settlo_core.dart';
import 'package:settlo_platform/settlo_platform.dart';

import 'support/fake_activity.dart';
import 'support/fake_session.dart';

/// Records what the app asks the native side to show.
class _FakeLiveActivities extends LiveActivities {
  final shown = <SettleUpActivity?>[];
  int permissionAsks = 0;

  @override
  Future<void> show(SettleUpActivity? activity) async => shown.add(activity);

  @override
  Future<bool> requestPermission() async {
    permissionAsks++;
    return true;
  }
}

/// Lets scheduled provider rebuilds and the fake reads finish.
Future<void> _settle() async {
  for (var i = 0; i < 5; i++) {
    await Future<void>.delayed(Duration.zero);
  }
}

void main() {
  final binding = TestWidgetsFlutterBinding.ensureInitialized();
  late _FakeLiveActivities native;
  late FakeActivityRepository activity;
  late ProviderContainer container;

  setUp(() {
    native = _FakeLiveActivities();
    activity = FakeActivityRepository(
      pending: [arjunRepaymentAnswer, rahulSettleUpAnswer],
    );
    container = ProviderContainer(
      overrides: [
        sessionProvider.overrideWith(() => FakeSessionNotifier(fakeSession)),
        activityRepositoryProvider.overrideWithValue(activity),
        liveActivitiesProvider.overrideWithValue(native),
      ],
    );
    addTearDown(container.dispose);
  });

  test('shows the settle-up awaiting you, ends when it resolves', () async {
    container.listen(liveActivitySyncProvider, (_, _) {});
    await _settle();
    expect(native.shown, [
      settleUpActivityFor([rahulSettleUpAnswer]),
    ]);
    expect(native.shown.single!.payer, 'Rahul');

    // Confirmed: the ledger moves on and only the repayment is left.
    activity.pending.remove(rahulSettleUpAnswer);
    container.read(ledgerRevisionProvider.notifier).bump();
    await _settle();
    expect(native.shown.last, isNull);
  });

  test('re-reads when the app comes back, since there is no push', () async {
    binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    container.listen(liveActivitySyncProvider, (_, _) {});
    await _settle();
    final reads = activity.calls.length;

    binding
      ..handleAppLifecycleStateChanged(AppLifecycleState.inactive)
      ..handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await _settle();
    expect(activity.calls.length, greaterThan(reads));
  });

  test('ends on sign-out', () async {
    container.listen(liveActivitySyncProvider, (_, _) {});
    await _settle();
    (container.read(sessionProvider.notifier) as FakeSessionNotifier).signOut();
    await _settle();
    expect(native.shown.last, isNull);
  });

  testWidgets('asks to notify on Activity with a settle-up, once', (
    tester,
  ) async {
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          theme: SettloTheme.dark(),
          home: const ActivityScreen(),
        ),
      ),
    );
    await tester.pump();
    container.invalidate(needsYouProvider);
    await tester.pump();
    expect(native.permissionAsks, 1);
  });

  testWidgets('does not ask when only a repayment waits', (tester) async {
    activity.pending.remove(rahulSettleUpAnswer);
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          theme: SettloTheme.dark(),
          home: const ActivityScreen(),
        ),
      ),
    );
    await tester.pump();
    expect(native.permissionAsks, 0);
  });
}
