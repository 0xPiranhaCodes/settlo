import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:settlo_auth/settlo_auth.dart';
import 'package:settlo_core/settlo_core.dart';

import 'support/fake_phone_auth.dart';
import 'support/golden.dart';

/// A container with the sign-in flow kept alive and a fake [PhoneAuth].
ProviderContainer _container() {
  final container = ProviderContainer(
    overrides: [phoneAuthProvider.overrideWithValue(FakePhoneAuth())],
  );
  addTearDown(container.dispose);
  container.listen(signInProvider, (_, _) {});
  return container;
}

/// The canvas sample number, as on the Phone and Onboarding artboards.
Future<ProviderContainer> _withNumber() async {
  final container = _container();
  container.read(signInProvider.notifier).updateNumber('9876543210');
  return container;
}

Future<ProviderContainer> _withCodeSent() async {
  final container = await _withNumber();
  await container.read(signInProvider.notifier).sendCode();
  return container;
}

typedef _Screen = ({
  String name,
  Future<ProviderContainer> Function() setUp,
  Widget screen,
  Future<void> Function(WidgetTester)? act,
});

final List<_Screen> _screens = [
  (
    name: 'welcome',
    setUp: () async => _container(),
    screen: const WelcomeScreen(),
    act: null,
  ),
  (
    name: 'phone',
    setUp: _withNumber,
    screen: const PhoneScreen(autofocus: false),
    act: null,
  ),
  (
    name: 'otp',
    setUp: _withCodeSent,
    screen: const OtpScreen(autofocus: false),
    // As on the artboard: three digits in, the fourth box focused, 0:24
    // left on the resend timer.
    act: (tester) async {
      await tester.enterText(find.byKey(const ValueKey('otp-code')), '481');
      await tester.pump(const Duration(seconds: 6));
    },
  ),
];

void main() {
  for (final device in SettloGoldenDevices.all) {
    for (final (themeName, theme) in [
      ('dark', SettloTheme.dark()),
      ('light', SettloTheme.light()),
    ]) {
      for (final s in _screens) {
        testWidgets('${device.name} $themeName ${s.name} golden', (
          tester,
        ) async {
          final container = await s.setUp();
          await pumpSettloGolden(
            tester,
            device: device,
            theme: theme,
            child: UncontrolledProviderScope(
              container: container,
              child: s.screen,
            ),
          );
          await s.act?.call(tester);

          await expectLater(
            find.byKey(settloGoldenSurfaceKey),
            matchesGoldenFile(
              'goldens/auth_${s.name}_${device.name}_$themeName.png',
            ),
          );
        });
      }
    }
  }
}
