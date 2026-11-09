import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:settlo_auth/settlo_auth.dart';
import 'package:settlo_core/settlo_core.dart';
import 'package:settlo_test_support/golden.dart';

import 'support/fake_phone_auth.dart';

/// Overflow checks for the sign-in screens at the compact size. Flutter
/// reports any overflow to the test binding, which fails the test; nothing
/// here consumes it (docs/release.md, UI comparison evidence).
void main() {
  final auth = FakePhoneAuth();

  Future<void> pump(
    WidgetTester tester,
    Widget screen, {
    double keyboard = 0,
    SignInError? error,
  }) async {
    final container = ProviderContainer(
      overrides: [phoneAuthProvider.overrideWithValue(auth)],
    );
    addTearDown(container.dispose);
    container.listen(signInProvider, (_, _) {});
    final controller = container.read(signInProvider.notifier)
      ..updateNumber('9876543210');
    await controller.sendCode();
    if (error == SignInError.invalidNumber) {
      controller.updateNumber('123');
      await controller.sendCode();
    } else if (error == SignInError.codeRejected) {
      auth.failure = PhoneAuthFailure.rejected;
      await controller.verifyCode('000000');
      auth.failure = null;
    }
    await pumpSettloGolden(
      tester,
      device: SettloGoldenDevices.compact360,
      theme: SettloTheme.dark(),
      child: UncontrolledProviderScope(
        container: container,
        child: Builder(
          builder: (context) => MediaQuery(
            data: MediaQuery.of(context)
                .copyWith(viewInsets: EdgeInsets.only(bottom: keyboard)),
            child: screen,
          ),
        ),
      ),
    );
  }

  final screens = <(String, Widget, SignInError?)>[
    ('Welcome', const WelcomeScreen(), null),
    ('Phone', const PhoneScreen(autofocus: false), null),
    ('Phone with an error', const PhoneScreen(), SignInError.invalidNumber),
    ('OTP', const OtpScreen(autofocus: false), null),
    ('OTP with an error', const OtpScreen(), SignInError.codeRejected),
  ];

  for (final (name, screen, error) in screens) {
    testWidgets('$name fits 360x800 without overflow', (tester) async {
      await pump(tester, screen, error: error);
      expect(find.byType(Scaffold), findsOneWidget);
    });

    testWidgets('$name scrolls instead of overflowing above a keyboard', (
      tester,
    ) async {
      await pump(tester, screen, error: error, keyboard: 336);
      expect(find.byType(Scaffold), findsOneWidget);
    });
  }

  testWidgets('the Welcome subtitle wraps as the canvas does at 390', (
    tester,
  ) async {
    await pumpSettloGolden(
      tester,
      device: SettloGoldenDevices.canvas390,
      theme: SettloTheme.dark(),
      child: const WelcomeScreen(),
    );
    final subtitle = find.textContaining('Flatmates, trips');
    // Two 16px lines at line height 1.5; the canvas breaks after "your".
    expect(tester.getSize(subtitle).height, 48);
    expect(
      tester.getRect(find.textContaining('Money between')).top,
      closeTo(300, 6),
    );
  });

  testWidgets('the primary action stays on screen at 360x800', (tester) async {
    for (final (_, screen, error) in screens) {
      await pump(tester, screen, error: error);
      final button = tester.getRect(find.byType(FilledButton));
      expect(button.bottom, lessThanOrEqualTo(800 - 24));
      expect(button.width, 360 - 48);
    }
  });
}
