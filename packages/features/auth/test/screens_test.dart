import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:settlo_auth/settlo_auth.dart';
import 'package:settlo_core/settlo_core.dart';

import 'fake_phone_auth.dart';

/// The sign-in routes with a fake [auth], starting at [location].
Future<GoRouter> _pump(
  WidgetTester tester,
  FakePhoneAuth auth, {
  String location = SettloRoutes.phone,
}) async {
  tester.view
    ..physicalSize = const Size(390, 844)
    ..devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final router = GoRouter(initialLocation: location, routes: authRoutes);
  addTearDown(router.dispose);
  await tester.pumpWidget(
    ProviderScope(
      overrides: [phoneAuthProvider.overrideWithValue(auth)],
      child: MaterialApp.router(
        theme: SettloTheme.dark(),
        routerConfig: router,
      ),
    ),
  );
  await tester.pumpAndSettle();
  return router;
}

final Finder _number = find.byKey(const ValueKey('phone-number'));
final Finder _code = find.byKey(const ValueKey('otp-code'));

/// Sends a code to +91 90000 00001 and lands on OTP.
Future<GoRouter> _toOtp(WidgetTester tester, FakePhoneAuth auth) async {
  final router = await _pump(tester, auth);
  await tester.enterText(_number, '9000000001');
  await tester.tap(find.text('Send code'));
  await tester.pumpAndSettle();
  return router;
}

/// Every string drawn on screen.
Set<String> _texts(WidgetTester tester) => {
  for (final text in tester.widgetList<RichText>(find.byType(RichText)))
    text.text.toPlainText(),
};

/// How many OTP boxes have the 2px action-coloured (gold) border.
int _goldBoxes(WidgetTester tester) =>
    tester.widgetList<Container>(find.byType(Container)).where((c) {
      final border = (c.decoration as BoxDecoration?)?.border as Border?;
      return border?.top.width == 2 &&
          border?.top.color == SettloColors.dark.action;
    }).length;

const _safetyNote =
    'This code is valid for 10 minutes. Settlo will never ask for it on a '
    'call or chat.';

void main() {
  late FakePhoneAuth auth;
  setUp(() => auth = FakePhoneAuth());

  group('Welcome', () {
    testWidgets('announces the Settlo lockup once', (tester) async {
      final semantics = tester.ensureSemantics();
      await _pump(tester, auth, location: SettloRoutes.welcome);

      expect(find.bySemanticsLabel('Settlo'), findsOneWidget);
      semantics.dispose();
    });

    testWidgets('marks the rows as examples and has one action', (
      tester,
    ) async {
      final router = await _pump(tester, auth, location: SettloRoutes.welcome);
      expect(find.text('example'), findsOneWidget);
      expect(find.byType(FilledButton), findsOneWidget);
      expect(find.byType(OutlinedButton), findsNothing);
      expect(find.byType(TextButton), findsNothing);

      await tester.tap(find.text('Continue with phone number'));
      await tester.pumpAndSettle();
      expect(router.state.uri.path, SettloRoutes.phone);
    });
  });

  group('Phone', () {
    testWidgets('preselects +91 as the text chip IN +91, no flag', (
      tester,
    ) async {
      await _pump(tester, auth);
      expect(find.text('IN'), findsOneWidget);
      expect(find.text('+91'), findsOneWidget);
      final flags = RegExp('[\u{1F1E6}-\u{1F1FF}]', unicode: true);
      expect(_texts(tester).where(flags.hasMatch), isEmpty);
    });

    testWidgets('the number field is 26px and focused on arrival', (
      tester,
    ) async {
      await _pump(tester, auth);
      final field = tester.widget<TextField>(_number);
      expect(field.style?.fontSize, 26);
      expect(field.keyboardType, TextInputType.phone);
      expect(tester.testTextInput.hasAnyClients, isTrue);
    });

    testWidgets('the country picker is reachable', (tester) async {
      await _pump(tester, auth);
      await tester.tap(find.byKey(const ValueKey('country-chip')));
      await tester.pumpAndSettle();
      expect(find.text('Country code'), findsOneWidget);

      await tester.tap(find.text('United Arab Emirates'));
      await tester.pumpAndSettle();
      expect(find.text('AE'), findsOneWidget);
      expect(find.text('+971'), findsOneWidget);

      await tester.enterText(_number, '501234567');
      await tester.tap(find.text('Send code'));
      await tester.pumpAndSettle();
      expect(auth.sent, ['+971501234567']);
    });

    testWidgets('an invalid number shows why and is not sent', (tester) async {
      final router = await _pump(tester, auth);
      await tester.enterText(_number, '12345');
      await tester.tap(find.text('Send code'));
      await tester.pumpAndSettle();

      expect(
        find.text('Enter a 10-digit mobile number starting with 6, 7, 8 or 9.'),
        findsOneWidget,
      );
      expect(auth.sent, isEmpty);
      expect(router.state.uri.path, SettloRoutes.phone);

      await tester.enterText(_number, '123456');
      await tester.pump();
      expect(find.textContaining('10-digit'), findsNothing);
    });

    testWidgets('a failed send is explained in plain words', (tester) async {
      auth.failure = PhoneAuthFailure.network;
      await _pump(tester, auth);
      await tester.enterText(_number, '9876543210');
      await tester.tap(find.text('Send code'));
      await tester.pumpAndSettle();
      expect(
        find.text(
          "We couldn't reach Settlo. Check your connection and try again.",
        ),
        findsOneWidget,
      );
    });

    testWidgets('Send code texts the E.164 number and opens OTP', (
      tester,
    ) async {
      final router = await _toOtp(tester, auth);
      expect(auth.sent, ['+919000000001']);
      expect(router.state.uri.path, SettloRoutes.otp);
      expect(
        find.textContaining('+91 90000 00001', findRichText: true),
        findsOneWidget,
      );
    });
  });

  group('OTP', () {
    testWidgets('six boxes; the focused one is gold', (tester) async {
      await _toOtp(tester, auth);
      expect(_goldBoxes(tester), 1);

      await tester.enterText(_code, '481');
      await tester.pump();
      expect(find.text('4'), findsOneWidget);
      expect(find.text('1'), findsOneWidget);
      expect(_goldBoxes(tester), 1);

      tester.widget<TextField>(_code).focusNode!.unfocus();
      await tester.pumpAndSettle();
      expect(_goldBoxes(tester), 0);
    });

    testWidgets('takes SMS autofill as a one-time code', (tester) async {
      await _toOtp(tester, auth);
      final field = tester.widget<TextField>(_code);
      expect(field.autofillHints, [AutofillHints.oneTimeCode]);
      expect(field.keyboardType, TextInputType.number);
    });

    testWidgets('a pasted code fills every box and verifies', (tester) async {
      await _toOtp(tester, auth);
      await tester.enterText(_code, 'Code: 123 456');
      await tester.pumpAndSettle();
      expect(auth.verified, [('+919000000001', '123456')]);
    });

    testWidgets('a partial code asks for all six digits', (tester) async {
      await _toOtp(tester, auth);
      await tester.enterText(_code, '123');
      await tester.tap(find.text('Verify and continue'));
      await tester.pumpAndSettle();
      expect(find.text('Enter all six digits of the code.'), findsOneWidget);
      expect(auth.verified, isEmpty);
    });

    testWidgets('a wrong code clears the boxes and says why', (tester) async {
      await _toOtp(tester, auth);
      auth.failure = PhoneAuthFailure.rejected;
      await tester.enterText(_code, '000000');
      await tester.pumpAndSettle();
      expect(find.textContaining("That code didn't work."), findsOneWidget);
      expect(tester.widget<TextField>(_code).controller!.text, isEmpty);
    });

    testWidgets('resend waits out the cooldown, then sends again', (
      tester,
    ) async {
      await _toOtp(tester, auth);
      expect(find.text('Resend in 0:30'), findsOneWidget);
      expect(find.text('Resend code'), findsNothing);

      await tester.pump(const Duration(seconds: 6));
      expect(find.text('Resend in 0:24'), findsOneWidget);

      await tester.pump(const Duration(seconds: 24));
      await tester.tap(find.text('Resend code'));
      await tester.pumpAndSettle();
      expect(auth.sent, ['+919000000001', '+919000000001']);
      expect(find.text('Resend in 0:30'), findsOneWidget);
    });

    testWidgets('screen readers hear one named code field', (tester) async {
      final semantics = tester.ensureSemantics();
      await _toOtp(tester, auth);
      final node = tester.getSemantics(
        find.bySemanticsLabel('Verification code, 6 digits'),
      );
      expect(node.flagsCollection.isTextField, isTrue);
      expect(find.bySemanticsLabel(RegExp('^Digit')), findsNothing);
      semantics.dispose();
    });

    testWidgets('change and resend have 44pt targets and labels', (
      tester,
    ) async {
      final semantics = tester.ensureSemantics();
      await _toOtp(tester, auth);
      await tester.pump(const Duration(seconds: resendCooldown));
      for (final label in ['change', 'Resend code']) {
        final target = find.byKey(ValueKey('action-$label'));
        final size = tester.getSize(target);
        expect(size.width, greaterThanOrEqualTo(44), reason: label);
        expect(size.height, greaterThanOrEqualTo(44), reason: label);
        // A tap at the target's edge, outside the glyphs, still lands.
        final rect = tester.getRect(target);
        expect(
          tester
              .hitTestOnBinding(rect.topLeft + const Offset(1, 1))
              .path
              .any((entry) => entry.target == tester.renderObject(target)),
          isTrue,
          reason: label,
        );
      }
      expect(find.bySemanticsLabel('Change number'), findsOneWidget);
      expect(find.bySemanticsLabel('Resend code'), findsOneWidget);
      await expectLater(tester, meetsGuideline(iOSTapTargetGuideline));
      await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));
      semantics.dispose();
    });

    testWidgets('change goes back to the number', (tester) async {
      final router = await _toOtp(tester, auth);
      await tester.tap(find.text('change'));
      await tester.pumpAndSettle();
      expect(router.state.uri.path, SettloRoutes.phone);
    });

    testWidgets('reveals nothing about the number beyond the number', (
      tester,
    ) async {
      await _toOtp(tester, auth);
      expect(_texts(tester), {
        '2 of 2',
        'Enter the code',
        'Sent to +91 90000 00001 · ',
        'change',
        'Fills in automatically',
        'Resend in 0:30',
        _safetyNote,
        'Verify and continue',
        '',
      });
    });

    testWidgets('opened without a code, goes to the number', (tester) async {
      final router = await _pump(tester, auth, location: SettloRoutes.otp);
      expect(router.state.uri.path, SettloRoutes.phone);
    });
  });
}
