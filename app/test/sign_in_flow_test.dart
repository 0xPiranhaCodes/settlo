import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:settlo/main.dart';
import 'package:settlo/router/router.dart';
import 'package:settlo_balances/settlo_balances.dart';
import 'package:settlo_core/settlo_core.dart';

import 'support/fake_home.dart';
import 'support/fake_phone_auth.dart';
import 'support/fake_session.dart';

/// Signs in when a code is verified, as Supabase's auth state change would.
class _SigningInAuth extends FakePhoneAuth {
  late FakeSessionNotifier session;

  @override
  Future<String?> verifyCode({
    required String phone,
    required String code,
  }) async {
    await super.verifyCode(phone: phone, code: code);
    session.signIn();
    return fakeSession.user.id;
  }
}

void main() {
  testWidgets('Welcome to Home through Phone and OTP', (tester) async {
    tester.view
      ..physicalSize = const Size(390, 844)
      ..devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final auth = _SigningInAuth();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          sessionProvider.overrideWith(() => FakeSessionNotifier(null)),
          phoneAuthProvider.overrideWithValue(auth),
          homeRepositoryProvider.overrideWithValue(
            FakeHomeRepository(homeEmpty),
          ),
        ],
        child: const SettloApp(),
      ),
    );
    await tester.pumpAndSettle();
    final container = ProviderScope.containerOf(
      tester.element(find.byType(SettloApp)),
    );
    auth.session =
        container.read(sessionProvider.notifier) as FakeSessionNotifier;

    await tester.tap(find.text('Continue with phone number'));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const ValueKey('phone-number')),
      '9000000001',
    );
    await tester.tap(find.text('Send code'));
    await tester.pumpAndSettle();
    expect(container.read(routerProvider).state.uri.path, SettloRoutes.otp);

    await tester.enterText(find.byKey(const ValueKey('otp-code')), '123456');
    await tester.pumpAndSettle();

    expect(auth.sent, ['+919000000001']);
    expect(auth.verified, [('+919000000001', '123456')]);
    expect(container.read(routerProvider).state.uri.path, SettloRoutes.home);
    expect(find.byType(HomeScreen), findsOneWidget);
  });
}
