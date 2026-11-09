import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:settlo/main.dart' as app;
import 'package:settlo_auth/settlo_auth.dart';
import 'package:settlo_balances/settlo_balances.dart';
import 'package:settlo_core/settlo_core.dart';
import 'package:settlo_expenses/settlo_expenses.dart';
import 'package:settlo_profile/settlo_profile.dart';
import 'package:settlo_spaces/settlo_spaces.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

const _upiChannel =
    'dev.flutter.pigeon.url_launcher_ios.UrlLauncherApi.launchUrl';

/// Encodes the successful value of url_launcher_ios's Pigeon enum without
/// making the app test depend directly on the platform implementation package.
final class _SuccessfulLaunch;

final class _UrlLauncherCodec extends StandardMessageCodec {
  const new();

  @override
  void writeValue(WriteBuffer buffer, Object? value) {
    if (value is _SuccessfulLaunch) {
      buffer.putUint8(129); // url_launcher_ios LaunchResult
      writeValue(buffer, 0); // LaunchResult.success
    } else {
      super.writeValue(buffer, value);
    }
  }
}

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('three flatmates split fairly and settle every balance', (
    tester,
  ) async {
    const launcherCodec = _UrlLauncherCodec();
    final launchedUpiUris = <Uri>[];
    binding.defaultBinaryMessenger.setMockMessageHandler(_upiChannel, (
      message,
    ) async {
      final arguments = launcherCodec.decodeMessage(message) as List<Object?>;
      final uri = Uri.parse(arguments.first! as String);
      expect(uri.scheme, 'upi');
      expect(uri.host, 'pay');
      launchedUpiUris.add(uri);
      return launcherCodec.encodeMessage(<Object?>[_SuccessfulLaunch()]);
    });
    addTearDown(() {
      binding.defaultBinaryMessenger.setMockMessageHandler(_upiChannel, null);
    });

    await app.main();
    await Supabase.instance.client.auth.signOut();
    addTearDown(Supabase.instance.client.auth.signOut);
    await _waitFor(tester, find.byType(WelcomeScreen));

    // Hand calculation, in paise:
    //   Groceries 100.00, equal, A paid: A 3334, B 3333, C 3333.
    //   Utilities  60.00, exact, B paid: A 1000, B 2000, C 3000.
    //   Dinner     100.01, shares 2:1:1, C paid: A 5001, B 2500, C 2500.
    // Fair shares: A 9335, B 7833, C 8833. Paid: A 10000, B 6000,
    // C 10001. Therefore balances are A +665, B -1833, C +1168.

    // Phase 1: Asha creates the flat, records all three expenses and checks
    // the resulting balance and agreed-split fairness view.
    await _signIn(tester, phone: '9000000001');
    await _setProfile(tester, name: 'Asha', upi: 'asha@upi');
    await _openSpaces(tester);
    await _createSpace(tester);
    await tester.tap(find.text('Flat 65'));
    await _waitFor(tester, find.text('Add first expense'));
    await _addExpense(
      tester,
      amount: '100.00',
      description: 'Groceries',
      payer: 'You',
      split: 'Equally',
    );
    await _addExpense(
      tester,
      amount: '60.00',
      description: 'Utilities',
      payer: 'Bela',
      split: 'Exact',
      values: const {'You': '10.00', 'Bela': '20.00', 'Charu': '30.00'},
    );
    await _addExpense(
      tester,
      amount: '100.01',
      description: 'Dinner',
      payer: 'Charu',
      split: 'Shares',
      values: const {'You': '2', 'Bela': '1', 'Charu': '1'},
    );
    await _checkLedger(
      tester,
      balanceLabel: 'YOU ARE OWED',
      youPaid: 'one hundred rupees',
      youShare: 'ninety-three rupees and thirty-five paise',
      difference: 'six rupees and sixty-five paise more than their share',
    );
    await _signOut(tester);

    // Phase 2: Charu joins the phone-linked space and independently checks
    // the same ledger from her identity.
    await _signIn(tester, phone: '9000000003');
    await _acceptSpaceClaim(tester);
    await _setProfile(tester, name: 'Charu', upi: 'charu@upi');
    await _openSpace(tester);
    await _checkLedger(
      tester,
      balanceLabel: 'YOU ARE OWED',
      youPaid: 'one hundred rupees and one paisa',
      youShare: 'eighty-eight rupees and thirty-three paise',
      difference: 'eleven rupees and sixty-eight paise more than their share',
    );
    await _signOut(tester);

    // Phase 3: Bela checks her -18.33 balance and fairness, then pays the two
    // simplified debts. The simulator has no UPI app, so the Pigeon platform
    // channel above fakes successful launches; Settlo still records nothing
    // until Bela explicitly confirms each payment in the app.
    await _signIn(tester, phone: '9000000002');
    await _acceptSpaceClaim(tester);
    await _setProfile(tester, name: 'Bela', upi: 'bela@upi');
    await _openSpace(tester);
    await _checkLedger(
      tester,
      balanceLabel: 'YOU OWE',
      youPaid: 'sixty rupees',
      youShare: 'seventy-eight rupees and thirty-three paise',
      difference:
          'eighteen rupees and thirty-three paise less than their share',
    );

    await _payAndConfirm(tester, amount: '₹11.68', payee: 'charu@upi');
    await _payAndConfirm(tester, amount: '₹6.65', payee: 'asha@upi');
    expect(launchedUpiUris, hasLength(2));
    expect(
      [for (final uri in launchedUpiUris) uri.queryParameters['pa']],
      ['charu@upi', 'asha@upi'],
    );

    // Product bug #82 leaves the originating summary stale after a settle-up;
    // exercise the product's pull-to-refresh path before the final UI check.
    await _openSpaces(tester);
    final spacesList = find.descendant(
      of: find.byType(SpacesListScreen),
      matching: find.byType(Scrollable),
    );
    await tester.drag(spacesList, const Offset(0, 360));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Flat 65'));
    await _waitFor(tester, find.text('Balances'));
    await tester.tap(find.text('Balances'));
    await _waitFor(tester, find.text('ALL SETTLED'));
    expect(find.text('Everyone is settled up.'), findsOneWidget);

    // A read-only server assertion proves every member—not only the signed-in
    // member shown by the final UI—ended at exactly zero paise.
    final rows = await Supabase.instance.client
        .from('space_member_balances')
        .select('balance_minor');
    expect(rows, hasLength(3));
    expect([
      for (final row in rows) row['balance_minor'] as int,
    ], everyElement(0));
  });
}

Future<void> _signIn(WidgetTester tester, {required String phone}) async {
  await _waitFor(tester, find.byType(WelcomeScreen));
  await tester.tap(find.text('Continue with phone number'));
  await _waitFor(tester, find.byType(PhoneScreen));
  await tester.enterText(find.byKey(const ValueKey('phone-number')), phone);
  await tester.tap(find.text('Send code'));
  await _waitFor(tester, find.byType(OtpScreen));
  await tester.enterText(find.byKey(const ValueKey('otp-code')), '123456');
  await _waitFor(tester, find.byType(HomeScreen));
}

Future<void> _setProfile(
  WidgetTester tester, {
  required String name,
  required String upi,
}) async {
  // Product bug #81 makes the profile sheet's Save action untappable under
  // the floating tab bar at 390x844. Use the same application RPC as that
  // sheet to establish test identities; this is not direct SQL seeding.
  await Supabase.instance.client.rpc<void>(
    'update_profile',
    params: {'p_name': name, 'p_upi_id': upi},
  );
  await tester.pumpAndSettle();
}

Future<void> _acceptSpaceClaim(WidgetTester tester) async {
  await _waitFor(tester, find.text('Accept'));
  await tester.tap(find.text('Accept'));
  await _waitFor(tester, find.text('Flat 65'));
}

Future<void> _signOut(WidgetTester tester) async {
  // Return to Home first so the profile route is reached consistently from
  // both the Spaces shell and a space detail route.
  await tester.tap(find.text('Home').last);
  await _waitFor(tester, find.byType(HomeScreen));
  await tester.tap(find.byType(SAvatar).first);
  await _waitFor(tester, find.byType(ProfileScreen));
  await _scrollTo(tester, find.text('Sign out'));
  await tester.tap(find.text('Sign out'));
  await _waitFor(tester, find.byType(WelcomeScreen));
}

Future<void> _openSpaces(WidgetTester tester) async {
  await tester.tap(find.text('Spaces').last);
  await _waitFor(tester, find.byType(SpacesListScreen));
}

Future<void> _openSpace(WidgetTester tester) async {
  await _openSpaces(tester);
  await _waitFor(tester, find.text('Flat 65'));
  await tester.tap(find.text('Flat 65'));
  await _waitFor(tester, find.text('Balances'));
}

Future<void> _createSpace(WidgetTester tester) async {
  await tester.tap(find.byTooltip('New space'));
  await _waitFor(tester, find.byType(CreateSpaceSheet));
  final fields = find.descendant(
    of: find.byType(CreateSpaceSheet),
    matching: find.byType(TextField),
  );
  await tester.enterText(fields.at(0), 'Flat 65');
  await tester.enterText(fields.at(1), '9000000002');
  await tester.enterText(fields.at(2), 'Bela');
  await tester.tap(find.text('Add person'));
  await tester.enterText(fields.at(1), '9000000003');
  await tester.enterText(fields.at(2), 'Charu');
  await tester.tap(find.text('Add person'));
  await _scrollTo(tester, find.text('Create space'));
  await tester.tap(find.text('Create space'));
  await _waitFor(tester, find.text('Flat 65'));
}

Future<void> _addExpense(
  WidgetTester tester, {
  required String amount,
  required String description,
  required String payer,
  required String split,
  Map<String, String> values = const {},
}) async {
  final add = find.textContaining('Add ').first;
  await _scrollTo(tester, add);
  await tester.tap(add);
  await _waitFor(tester, find.byType(AddExpenseSheet));
  await _enterLabeled(tester, 'Amount in rupees', amount);
  await _enterLabeled(tester, 'What for', description);
  if (payer != 'You') {
    await _scrollTo(tester, find.text(payer));
    await tester.tap(find.text(payer).first);
  }
  if (split != 'Equally') {
    await _scrollTo(tester, find.text(split));
    await tester.tap(find.text(split));
    final unit = split == 'Exact' ? 'in rupees' : 'shares';
    for (final entry in values.entries) {
      await _enterLabeled(tester, '${entry.key}, $unit', entry.value);
    }
  }
  await _scrollTo(tester, find.text('Save expense'));
  await tester.tap(find.text('Save expense'));
  await _waitFor(tester, find.text(description));
}

Future<void> _checkLedger(
  WidgetTester tester, {
  required String balanceLabel,
  required String youPaid,
  required String youShare,
  required String difference,
}) async {
  await _scrollTo(tester, find.text('Balances'));
  await tester.tap(find.text('Balances'));
  await _waitFor(tester, find.text(balanceLabel));
  await _scrollTo(
    tester,
    _semanticsWidget('You paid $youPaid, fair share $youShare, $difference'),
  );
  expect(
    _semanticsWidget('You paid $youPaid, fair share $youShare, $difference'),
    findsOneWidget,
  );
}

Future<void> _payAndConfirm(
  WidgetTester tester, {
  required String amount,
  required String payee,
}) async {
  await _scrollTo(tester, find.text('Pay').first);
  await tester.tap(find.text('Pay').first);
  await _waitFor(tester, find.text('Pay $amount via UPI'));
  expect(find.textContaining(payee), findsOneWidget);
  await tester.tap(find.text('Pay $amount via UPI'));
  await _waitFor(tester, find.text('Yes, I paid'));
  await tester.tap(find.text('Yes, I paid'));
  await _waitFor(tester, find.text('Balances'));
}

Future<void> _enterLabeled(
  WidgetTester tester,
  String label,
  String value,
) async {
  final semantics = _semanticsWidget(label);
  await _scrollTo(tester, semantics);
  final editable = find.descendant(
    of: semantics,
    matching: find.byType(EditableText),
  );
  await tester.enterText(editable, value);
}

Finder _semanticsWidget(String label) => find.byWidgetPredicate(
  (widget) => widget is Semantics && widget.properties.label == label,
  description: 'Semantics(label: $label)',
);

Future<void> _scrollTo(WidgetTester tester, Finder finder) async {
  if (finder.evaluate().isEmpty) {
    final scrollables = find.byType(Scrollable);
    if (scrollables.evaluate().isEmpty) fail('Could not find $finder');
    await tester.scrollUntilVisible(
      finder,
      180,
      scrollable: scrollables.last,
      maxScrolls: 20,
    );
  }
  await tester.ensureVisible(finder.first);
  await tester.pumpAndSettle();
}

Future<void> _waitFor(
  WidgetTester tester,
  Finder finder, {
  Duration timeout = const Duration(seconds: 25),
}) async {
  final end = DateTime.now().add(timeout);
  while (finder.evaluate().isEmpty) {
    if (DateTime.now().isAfter(end)) {
      fail('Timed out waiting for $finder');
    }
    await tester.pump(const Duration(milliseconds: 200));
  }
  await tester.pumpAndSettle();
}
