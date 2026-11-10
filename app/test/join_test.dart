import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:settlo/main.dart';
import 'package:settlo/router/router.dart';
import 'package:settlo_auth/settlo_auth.dart';
import 'package:settlo_core/settlo_core.dart';

import 'support/fake_phone_auth.dart';
import 'support/fake_session.dart';

const _token =
    'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa';
const _coldToken =
    'bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb';
const _warmToken =
    'cccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccc';

final class _Invites implements InvitesRepository {
  new({this.redeemCompleter, this.redeemFailure});

  final Completer<void>? redeemCompleter;
  final InviteFailure? redeemFailure;
  int redeemCalls = 0;
  int declineCalls = 0;
  final inspected = <String>[];
  final declined = <String>[];

  @override
  Future<InvitePreview?> inspect(String token) async {
    inspected.add(token);
    return InvitePreview(
      kind: 'space',
      inviterName: token == _warmToken ? 'Bilal' : 'Satheesh',
      subjectName: token == _warmToken ? 'Flat B' : 'Flat 402',
      maskedPhone: '+91 981•••••44',
    );
  }

  @override
  Future<void> redeem(String token, {required String idempotencyKey}) async {
    redeemCalls++;
    if (redeemFailure case final failure?) throw InviteException(failure);
    final completer = redeemCompleter;
    if (completer != null) await completer.future;
  }

  @override
  Future<void> decline(String token, {required String idempotencyKey}) async {
    declineCalls++;
    declined.add(token);
  }

  @override
  Future<String> issueLoan(String loanId, {required String idempotencyKey}) =>
      throw UnimplementedError();

  @override
  Future<String> issueSpace(
    String memberId, {
    required String idempotencyKey,
  }) => throw UnimplementedError();
}

final class _Links implements DeepLinkSource {
  new(this.initial, this.controller);

  @override
  final Future<Uri?> initial;
  final StreamController<Uri> controller;

  @override
  Stream<Uri> get changes => controller.stream;
}

final class _SigningInAuth extends FakePhoneAuth {
  late FakeSessionNotifier session;

  @override
  Future<void> verifyCode({required String phone, required String code}) async {
    await super.verifyCode(phone: phone, code: code);
    session.signIn();
  }
}

GoRouter _router(WidgetTester tester) =>
    ProviderScope.containerOf(tester.element(find.byType(SettloApp)))
        .read(routerProvider);

Future<void> _pump(
  WidgetTester tester,
  _Invites invites, {
  required bool signedIn,
}) async {
  tester.view
    ..physicalSize = const Size(390, 844)
    ..devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    fakeSessionApp(signedIn ? fakeSession : null, invites: invites),
  );
  await tester.pumpAndSettle();
  _router(tester).go(SettloRoutes.join(_token));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('shows only Join trust copy before verification', (tester) async {
    await _pump(tester, _Invites(), signedIn: false);

    expect(find.text('Satheesh added you to Flat 402'), findsOneWidget);
    expect(find.text('+91 981•••••44'), findsOneWidget);
    expect(find.text('Recorded for'), findsOneWidget);
    expect(find.textContaining('₹'), findsNothing);
    expect(find.text("This isn't me"), findsOneWidget);
  });

  testWidgets("This isn't me records decline and exits", (tester) async {
    final invites = _Invites();
    await _pump(tester, invites, signedIn: false);

    await tester.tap(find.text("This isn't me"));
    await tester.pumpAndSettle();

    expect(invites.declineCalls, 1);
    expect(find.byType(WelcomeScreen), findsOneWidget);
  });

  testWidgets('primary action ignores a no-pump double tap', (tester) async {
    final completer = Completer<void>();
    final invites = _Invites(redeemCompleter: completer);
    await _pump(tester, invites, signedIn: true);

    final primary = find.text('Verify my number to see the ledger');
    await tester.tap(primary);
    await tester.tap(primary);
    expect(invites.redeemCalls, 1);

    completer.complete();
    await tester.pumpAndSettle();
  });

  testWidgets('custom-scheme invite routes on cold and warm delivery', (
    tester,
  ) async {
    final controller = StreamController<Uri>();
    addTearDown(controller.close);
    final links = _Links(
      Future.value(Uri.parse('settlo://join/$_coldToken')),
      controller,
    );
    await tester.pumpWidget(
      fakeSessionApp(
        null,
        invites: _Invites(),
        overrides: [deepLinkSourceProvider.overrideWithValue(links)],
      ),
    );
    await tester.pumpAndSettle();
    final router = _router(tester);
    expect(router.state.uri.path, SettloRoutes.join(_coldToken));
    expect(find.byType(JoinScreen), findsOneWidget);

    router.go(SettloRoutes.welcome);
    await tester.pumpAndSettle();
    controller.add(Uri.parse('settlo://join/$_warmToken'));
    await tester.pumpAndSettle();
    expect(router.state.uri.path, SettloRoutes.join(_warmToken));
    expect(find.byType(JoinScreen), findsOneWidget);
  });

  testWidgets('a second warm link rebuilds Join before acting on it', (
    tester,
  ) async {
    final controller = StreamController<Uri>();
    addTearDown(controller.close);
    final invites = _Invites();
    await tester.pumpWidget(
      fakeSessionApp(
        null,
        invites: invites,
        overrides: [
          deepLinkSourceProvider.overrideWithValue(
            _Links(
              Future.value(Uri.parse('settlo://join/$_coldToken')),
              controller,
            ),
          ),
        ],
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Satheesh added you to Flat 402'), findsOneWidget);

    controller.add(Uri.parse('settlo://join/$_warmToken'));
    await tester.pumpAndSettle();
    expect(find.text('Bilal added you to Flat B'), findsOneWidget);
    await tester.tap(find.text("This isn't me"));
    await tester.pumpAndSettle();

    expect(invites.inspected, [_coldToken, _warmToken]);
    expect(invites.declined, [_warmToken]);
  });

  testWidgets('wrong phone after OTP is visible on signed-in Home', (
    tester,
  ) async {
    tester.view
      ..physicalSize = const Size(390, 844)
      ..devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final auth = _SigningInAuth();
    await tester.pumpWidget(
      fakeSessionApp(
        null,
        invites: _Invites(redeemFailure: InviteFailure.wrongPhone),
        overrides: [phoneAuthProvider.overrideWithValue(auth)],
      ),
    );
    await tester.pumpAndSettle();
    final container = ProviderScope.containerOf(
      tester.element(find.byType(SettloApp)),
    );
    auth.session =
        container.read(sessionProvider.notifier) as FakeSessionNotifier;
    container.read(routerProvider).go(SettloRoutes.join(_token));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Verify my number to see the ledger'));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const ValueKey('phone-number')),
      '9000000001',
    );
    await tester.tap(find.text('Send code'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const ValueKey('otp-code')), '123456');
    await tester.pumpAndSettle();

    expect(container.read(routerProvider).state.uri.path, SettloRoutes.home);
    expect(find.textContaining('different number'), findsOneWidget);
  });

  testWidgets('router exception recovery returns signed out to Welcome', (
    tester,
  ) async {
    await tester.pumpWidget(fakeSessionApp(null, invites: _Invites()));
    await tester.pumpAndSettle();
    final router = _router(tester)..go('settlo://join/recovered-token');
    await tester.pumpAndSettle();

    expect(router.state.uri.path, SettloRoutes.welcome);
    expect(find.byType(WelcomeScreen), findsOneWidget);
  });

  test('normalizes only the supported custom-scheme shape', () {
    expect(
      invitePathForUri(Uri.parse('settlo://join/$_token')),
      SettloRoutes.join(_token),
    );
    expect(invitePathForUri(Uri.parse('settlo://join/abc')), isNull);
    expect(
      invitePathForUri(Uri.parse('settlo://join/${_token.toUpperCase()}')),
      isNull,
    );
    expect(invitePathForUri(Uri.parse('settlo://join/${_token}a')), isNull);
    expect(invitePathForUri(Uri.parse('settlo://other/abc')), isNull);
    expect(invitePathForUri(Uri.parse('https://example.com/join/abc')), isNull);
  });
}
