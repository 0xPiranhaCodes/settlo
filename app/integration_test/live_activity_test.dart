import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:integration_test/integration_test.dart';
import 'package:settlo_core/settlo_core.dart';
import 'package:settlo_platform/settlo_platform.dart';

/// Shows a settle-up through the real native side: the Live Activity and
/// Dynamic Island on iOS, the ongoing notification on Android. Then waits
/// for its Confirm link to reach the router, so tap Confirm on the device
/// (or `xcrun simctl openurl booted settlo://app/spaces/s1/settle-ups/e1`).
/// Needs no backend. Ends the activity either way.
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  const waitSeconds = int.fromEnvironment('WAIT_SECONDS', defaultValue: 60);

  testWidgets('Confirm opens the confirm route, then the activity ends', (
    tester,
  ) async {
    final router = GoRouter(
      routes: [
        GoRoute(path: '/', builder: (_, _) => _page('Waiting')),
        GoRoute(
          path: SettloRoutes.confirmSettlementPattern,
          builder: (_, state) =>
              _page('Confirm ${state.pathParameters['expenseId']}'),
        ),
      ],
    );
    addTearDown(router.dispose);
    await tester.pumpWidget(
      MaterialApp.router(theme: SettloTheme.dark(), routerConfig: router),
    );

    const activities = LiveActivities();
    addTearDown(() => activities.show(null));
    await activities.requestPermission();
    await activities.show(
      SettleUpActivity(
        id: 'e1',
        spaceId: 's1',
        spaceName: 'Flat 402',
        payer: 'Priya',
        amount: const Paise.rupees(2100),
        recordedAt: DateTime.now().subtract(const Duration(minutes: 2)),
      ),
    );

    final end = DateTime.now().add(const Duration(seconds: waitSeconds));
    while (find.text('Confirm e1').evaluate().isEmpty) {
      if (DateTime.now().isAfter(end)) fail('Confirm was not tapped');
      await tester.pump(const Duration(milliseconds: 200));
    }
    expect(router.state.uri.path, SettloRoutes.confirmSettlement('s1', 'e1'));
  });
}

Widget _page(String text) => Scaffold(body: Center(child: Text(text)));
