import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:settlo_auth/settlo_auth.dart';
import 'package:settlo_core/settlo_core.dart';

import 'fake_phone_auth.dart';

void main() {
  late FakePhoneAuth auth;
  late ProviderContainer container;
  SignInController controller() => container.read(signInProvider.notifier);
  SignInState state() => container.read(signInProvider);

  setUp(() {
    auth = FakePhoneAuth();
    container = ProviderContainer(
      overrides: [phoneAuthProvider.overrideWithValue(auth)],
    )..listen(signInProvider, (_, _) {});
  });
  tearDown(() => container.dispose());

  test('starts in India with nothing entered', () {
    expect(state().country, Country.india);
    expect(state().national, '');
    expect(state().sentTo, isNull);
  });

  test('an invalid number is not sent', () async {
    controller().updateNumber('98765');
    expect(await controller().sendCode(), isFalse);
    expect(state().error, SignInError.invalidNumber);
    expect(auth.sent, isEmpty);
  });

  test('a valid number is sent in E.164 and remembered', () async {
    controller().updateNumber('90000 00001');
    expect(await controller().sendCode(), isTrue);
    expect(auth.sent, ['+919000000001']);
    expect(state().sentTo, '+919000000001');
    expect(state().error, isNull);
    expect(state().busy, isFalse);
  });

  test('editing the number clears the error', () async {
    controller().updateNumber('1');
    await controller().sendCode();
    controller().updateNumber('12');
    expect(state().error, isNull);
  });

  test('send failures map to what the person can do', () async {
    controller().updateNumber('9876543210');
    for (final (failure, error) in [
      (PhoneAuthFailure.rejected, SignInError.sendRejected),
      (PhoneAuthFailure.rateLimited, SignInError.rateLimited),
      (PhoneAuthFailure.network, SignInError.network),
    ]) {
      auth.failure = failure;
      expect(await controller().sendCode(), isFalse);
      expect(state().error, error);
      expect(state().sentTo, isNull);
    }
  });

  group('after a code is sent', () {
    setUp(() async {
      controller().updateNumber('9000000001');
      await controller().sendCode();
    });

    test('verifies six digits against the same number', () async {
      await controller().verifyCode('123456');
      expect(auth.verified, [('+919000000001', '123456')]);
      expect(state().error, isNull);
    });

    test('asks for all six digits first', () async {
      await controller().verifyCode('1234');
      expect(state().error, SignInError.incompleteCode);
      expect(auth.verified, isEmpty);
    });

    test('a wrong or expired code says so', () async {
      auth.failure = PhoneAuthFailure.rejected;
      await controller().verifyCode('000000');
      expect(state().error, SignInError.codeRejected);
    });

    test('resends to the number the code went to', () async {
      controller().updateNumber('9999999999');
      expect(await controller().resendCode(), isTrue);
      expect(auth.sent, ['+919000000001', '+919000000001']);
    });
  });

  test('cannot verify or resend before sending', () async {
    expect(await controller().resendCode(), isFalse);
    await controller().verifyCode('123456');
    expect(auth.verified, isEmpty);
  });

  test('error copy is plain: sentence case, no exclamation marks', () {
    for (final error in SignInError.values) {
      for (final country in Country.all) {
        final message = error.message(country);
        expect(message, isNot(contains('!')));
        expect(message[0], message[0].toUpperCase());
        expect(message, endsWith('.'));
      }
    }
  });
}
