import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:settlo/main.dart' as app;
import 'package:settlo_activity/settlo_activity.dart';
import 'package:settlo_auth/settlo_auth.dart';
import 'package:settlo_balances/settlo_balances.dart';
import 'package:settlo_core/settlo_core.dart';
import 'package:settlo_loans/settlo_loans.dart';
import 'package:settlo_profile/settlo_profile.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

const _urlLauncherChannel =
    'dev.flutter.pigeon.url_launcher_ios.UrlLauncherApi.launchUrl';

/// Encodes url_launcher_ios's successful Pigeon result without depending on
/// the platform implementation package from the app test.
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

  testWidgets('a borrower records repayments for the lender to answer', (
    tester,
  ) async {
    const principalMinor = 10000000; // ₹1,00,000
    const installmentMinor = 2500000; // ₹25,000
    const reference1 = 'UPI LOAN 9201';
    const reference2 = 'UPI LOAN 9202';
    const reference3 = 'UPI LOAN 9203';
    const disputeReason = 'Bank statement has no matching credit';

    // Hand calculation, all integer paise:
    //   principal                         1,00,00,000
    //   confirmed #1                     -25,00,000
    //   disputed #2                              0
    //   confirmed #3                     -25,00,000
    //   final repaid                       50,00,000 (50%)
    //   final outstanding                  50,00,000
    // Four monthly instalments are due from the month after start. Starting
    // today means nothing is overdue today, so the loan remains on track.
    expect(principalMinor - installmentMinor, 7500000);
    expect(principalMinor - 2 * installmentMinor, 5000000);

    const codec = _UrlLauncherCodec();
    final launchedUris = <Uri>[];
    binding.defaultBinaryMessenger.setMockMessageHandler(_urlLauncherChannel, (
      message,
    ) async {
      final arguments = codec.decodeMessage(message) as List<Object?>;
      launchedUris.add(Uri.parse(arguments.first! as String));
      return codec.encodeMessage(<Object?>[_SuccessfulLaunch()]);
    });
    addTearDown(() {
      binding.defaultBinaryMessenger.setMockMessageHandler(
        _urlLauncherChannel,
        null,
      );
    });

    await app.main();
    await Supabase.instance.client.auth.signOut();
    addTearDown(Supabase.instance.client.auth.signOut);
    await _waitFor(tester, find.byType(WelcomeScreen));

    // Asha lends to Bela entirely through the New loan UI.
    await _signIn(tester, phone: '9000000001');
    await _setProfile(tester, name: 'Asha');
    await _openLoans(tester);
    await tester.tap(find.byTooltip('New loan'));
    await _waitFor(tester, find.byType(NewLoanSheet));
    await _enterSemantics(tester, 'Principal in rupees', '100000');
    await _enterField(tester, 'Phone number', '9000000002');
    await _enterField(tester, 'Their name', 'Bela');
    await tester.tap(find.text('Add person'));
    await tester.pumpAndSettle();
    await tester.enterText(find.widgetWithText(TextField, 'Flexible'), '25000');
    FocusManager.instance.primaryFocus?.unfocus();
    await tester.pumpAndSettle();
    await _scrollTo(tester, find.text('Create loan and share'));
    await tester.tap(find.text('Create loan and share'));
    await _waitFor(tester, find.byType(LoanDetailScreen));
    expect(launchedUris, hasLength(1));
    expect(launchedUris.single.host, 'wa.me');
    expect(launchedUris.single.path, '/919000000002');
    await _assertLoanUi(tester, percent: 0, outstandingMinor: principalMinor);
    final loanId = await _loanId();
    await _signOut(tester);

    // Bela verifies the invited number, accepts the loan claim and records
    // the first ₹25,000 with a reference. Pending money must not move the ring.
    await _signIn(tester, phone: '9000000002');
    await _waitFor(tester, find.text('Loan with Asha'));
    await tester.tap(find.text('Accept'));
    await _waitForGone(tester, find.text('Loan with Asha'));
    await _setProfile(tester, name: 'Bela');
    await _openLoan(tester);
    await _assertLoanUi(tester, percent: 0, outstandingMinor: principalMinor);
    await _recordRepayment(tester, reference: reference1);
    await _assertLoanUi(tester, percent: 0, outstandingMinor: principalMinor);
    expect(find.text('awaiting Asha'), findsOneWidget);
    await _signOut(tester);

    // Asha opens Activity > Needs you, checks the receipt's projected balance,
    // and confirms the first repayment.
    await _signIn(tester, phone: '9000000001');
    await _openActivity(tester);
    await _waitFor(tester, find.text('Needs you · 1'));
    expect(find.text('Bela recorded a ₹25,000 repayment'), findsOneWidget);
    await tester.tap(find.text('Needs you · 1'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Review'));
    await _waitFor(tester, find.byType(ConfirmRepaymentScreen));
    await _assertReceipt(tester, reference: reference1, afterMinor: 7500000);
    await _scrollTo(tester, find.text('Confirm ₹25,000 received'));
    await tester.tap(find.text('Confirm ₹25,000 received'));
    await _waitFor(tester, find.textContaining('already been answered'));
    await tester.tap(find.byTooltip('Back'));
    await _waitFor(tester, find.byType(ActivityScreen));
    await _openLoan(tester);
    await _assertLoanUi(tester, percent: 25, outstandingMinor: 7500000);
    await _signOut(tester);

    // Bela records the same instalment again. Asha disputes it with a reason;
    // disputed money never changes repaid or outstanding.
    await _signIn(tester, phone: '9000000002');
    await _openLoan(tester);
    await _recordRepayment(tester, reference: reference2);
    await _assertLoanUi(tester, percent: 25, outstandingMinor: 7500000);
    await _signOut(tester);

    await _signIn(tester, phone: '9000000001');
    await _openActivity(tester);
    await _waitFor(tester, find.text('Needs you · 1'));
    await tester.tap(find.text('Review'));
    await _waitFor(tester, find.byType(ConfirmRepaymentScreen));
    await _assertReceipt(tester, reference: reference2, afterMinor: 5000000);
    await _scrollTo(tester, find.text("Didn't receive this"));
    await tester.tap(find.text("Didn't receive this"));
    final reason = _semantics('Reason');
    await _waitFor(tester, reason);
    await tester.enterText(
      find.descendant(of: reason, matching: find.byType(EditableText)),
      disputeReason,
    );
    FocusManager.instance.primaryFocus?.unfocus();
    await tester.pumpAndSettle();
    final dispute = find.widgetWithText(FilledButton, 'Mark as not received');
    await _scrollTo(tester, dispute);
    await tester.tap(dispute);
    await _waitForGone(tester, find.text('Mark as not received'));
    await tester.tap(find.byTooltip('Back'));
    await _waitFor(tester, find.byType(ActivityScreen));
    await _openLoan(tester);
    await _assertLoanUi(tester, percent: 25, outstandingMinor: 7500000);
    expect(find.text('“$disputeReason”'), findsOneWidget);
    await _signOut(tester);

    // Bela records a corrected instalment and Asha confirms it. Exactly two
    // repayments now count: ₹50,000 repaid and ₹50,000 outstanding.
    await _signIn(tester, phone: '9000000002');
    await _openLoan(tester);
    await _recordRepayment(tester, reference: reference3);
    await _assertLoanUi(tester, percent: 25, outstandingMinor: 7500000);
    await _signOut(tester);

    await _signIn(tester, phone: '9000000001');
    await _openActivity(tester);
    await _waitFor(tester, find.text('Needs you · 1'));
    await tester.tap(find.text('Review'));
    await _waitFor(tester, find.byType(ConfirmRepaymentScreen));
    await _assertReceipt(tester, reference: reference3, afterMinor: 5000000);
    await _scrollTo(tester, find.text('Confirm ₹25,000 received'));
    await tester.tap(find.text('Confirm ₹25,000 received'));
    await _waitFor(tester, find.textContaining('already been answered'));
    await tester.tap(find.byTooltip('Back'));
    await _waitFor(tester, find.byType(ActivityScreen));
    expect(find.text('Needs you'), findsOneWidget);
    expect(find.textContaining('Needs you ·'), findsNothing);

    // Activity is asserted in the UI and then by its read-only RPC result:
    // three records, two confirmations, one dispute and the loan creation.
    await _scrollTo(tester, find.text("You said a repayment didn't arrive"));
    expect(find.text("You said a repayment didn't arrive"), findsOneWidget);
    await _scrollTo(tester, find.text('You recorded a loan'));
    expect(find.text('You recorded a loan'), findsOneWidget);
    final activity = await Supabase.instance.client.rpc<List<dynamic>>(
      'activity_feed',
      params: {'p_limit': 30},
    );
    final loanActivity = activity
        .cast<Map<String, dynamic>>()
        .where((row) => row['loan_id'] == loanId)
        .toList();
    expect(
      loanActivity.map((row) => row['action']),
      containsAll(<String>['created', 'recorded', 'confirmed', 'disputed']),
    );
    expect(
      loanActivity.where((row) => row['action'] == 'recorded'),
      hasLength(3),
    );
    expect(
      loanActivity.where((row) => row['action'] == 'confirmed'),
      hasLength(2),
    );
    expect(
      loanActivity.where((row) => row['action'] == 'disputed'),
      hasLength(1),
    );

    await _openLoan(tester);
    await _assertLoanUi(tester, percent: 50, outstandingMinor: 5000000);

    // Read-only server truth for the hand calculation above. Pending is zero;
    // the disputed repayment stays visible but contributes no principal.
    final summaries = await Supabase.instance.client
        .from('loan_summaries')
        .select(
          'loan_id,repaid_minor,outstanding_minor,confirmed_count,'
          'pending_count,disputed_count,pending_minor,installments_total,'
          'installments_paid,on_track',
        )
        .eq('loan_id', loanId);
    expect(summaries, hasLength(1));
    expect(summaries.single, <String, dynamic>{
      'loan_id': loanId,
      'repaid_minor': 5000000,
      'outstanding_minor': 5000000,
      'confirmed_count': 2,
      'pending_count': 0,
      'disputed_count': 1,
      'pending_minor': 0,
      'installments_total': 4,
      'installments_paid': 2,
      'on_track': true,
    });
  });
}

Future<String> _loanId() async {
  final rows = await Supabase.instance.client
      .from('loan_summaries')
      .select('loan_id');
  expect(rows, hasLength(1));
  return rows.single['loan_id'] as String;
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

Future<void> _setProfile(WidgetTester tester, {required String name}) async {
  await tester.tap(find.byType(SAvatar).first);
  await _waitFor(tester, find.byType(ProfileScreen));
  await _scrollTo(tester, find.text('Name and UPI ID'));
  await tester.tap(find.text('Name and UPI ID'));
  await _waitFor(tester, find.byKey(const ValueKey('profile-name')));
  await tester.enterText(find.byKey(const ValueKey('profile-name')), name);
  FocusManager.instance.primaryFocus?.unfocus();
  await tester.pumpAndSettle();
  await _scrollTo(tester, find.text('Save'));
  await tester.tap(find.text('Save'));
  await _waitForGone(tester, find.byKey(const ValueKey('profile-name')));
  await tester.tap(find.text('Home').last);
  await _waitFor(tester, find.byType(HomeScreen));
}

Future<void> _signOut(WidgetTester tester) async {
  await tester.tap(find.text('Home').last);
  await _waitFor(tester, find.byType(HomeScreen));
  await tester.tap(find.byType(SAvatar).first);
  await _waitFor(tester, find.byType(ProfileScreen));
  await _scrollTo(tester, find.text('Sign out'));
  await tester.tap(find.text('Sign out'));
  await _waitFor(tester, find.byType(WelcomeScreen));
}

Future<void> _openLoans(WidgetTester tester) async {
  await tester.tap(find.text('Loans').last);
  await _waitFor(tester, find.byType(LoanScreen));
}

Future<void> _openLoan(WidgetTester tester) async {
  await _openLoans(tester);
  await _waitFor(tester, find.textContaining('· interest free'));
  await tester.tap(find.textContaining('· interest free').first);
  await _waitFor(tester, find.byType(LoanDetailScreen));
}

Future<void> _openActivity(WidgetTester tester) async {
  await tester.tap(find.text('Activity').last);
  await _waitFor(tester, find.byType(ActivityScreen));
}

Future<void> _recordRepayment(
  WidgetTester tester, {
  required String reference,
}) async {
  await _scrollTo(tester, find.text('Record repayment'));
  await tester.tap(find.text('Record repayment'));
  await _waitFor(tester, find.textContaining('Record repayment ·'));
  expect(find.widgetWithText(TextField, '25,000'), findsOneWidget);
  await tester.enterText(
    find.widgetWithText(TextField, 'UPI or bank reference'),
    reference,
  );
  FocusManager.instance.primaryFocus?.unfocus();
  await tester.pumpAndSettle();
  final save = find.widgetWithText(FilledButton, 'Record repayment').last;
  await _scrollTo(tester, save);
  await tester.tap(save);
  await _waitForGone(tester, find.textContaining('Record repayment ·'));
  await _waitFor(tester, find.text('awaiting Asha'));
}

Future<void> _assertReceipt(
  WidgetTester tester, {
  required String reference,
  required int afterMinor,
}) async {
  final after = Paise(afterMinor);
  expect(find.textContaining('ref $reference'), findsOneWidget);
  expect(_semantics('Outstanding after, ${spokenInr(after)}'), findsOneWidget);
  expect(find.text(formatInr(after)), findsOneWidget);
}

Future<void> _assertLoanUi(
  WidgetTester tester, {
  required int percent,
  required int outstandingMinor,
}) async {
  final today = indiaDate(DateTime.now());
  final dueDay = math.min(today.day, 28);
  final nextDue = DateTime(today.year, today.month + 1, dueDay);
  final ends = DateTime(today.year, today.month + 4);
  expect(_semantics('$percent percent repaid'), findsOneWidget);
  expect(find.text('$percent%'), findsOneWidget);
  expect(
    find.byWidgetPredicate(
      (widget) =>
          widget is MoneyText && widget.amount == Paise(outstandingMinor),
      description: 'MoneyText(amount: $outstandingMinor paise)',
    ),
    findsOneWidget,
  );
  expect(
    _semantics(
      'Instalment, twenty-five thousand rupees, monthly · '
      '${_ordinal(dueDay)}',
    ),
    findsOneWidget,
  );
  expect(
    _semantics(
      'Next due, ${_dayMonth(nextDue)}, '
      'in ${nextDue.difference(today).inDays} days',
    ),
    findsOneWidget,
  );
  expect(
    _semantics('Schedule, On track, ends ${_monthYear(ends)}'),
    findsOneWidget,
  );
}

const _months = [
  'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', //
  'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
];

String _dayMonth(DateTime d) => '${d.day} ${_months[d.month - 1]}';

String _monthYear(DateTime d) => '${_months[d.month - 1]} ${d.year}';

String _ordinal(int n) =>
    '$n${switch (n % 100) {
      11 || 12 || 13 => 'th',
      _ => switch (n % 10) {
        1 => 'st',
        2 => 'nd',
        3 => 'rd',
        _ => 'th',
      },
    }}';

Future<void> _enterField(
  WidgetTester tester,
  String label,
  String value,
) async {
  final field = find.ancestor(
    of: find.text(label),
    matching: find.byType(TextField),
  );
  await _scrollTo(tester, field);
  await tester.enterText(field, value);
}

Future<void> _enterSemantics(
  WidgetTester tester,
  String label,
  String value,
) async {
  final semantics = _semantics(label);
  await _scrollTo(tester, semantics);
  await tester.enterText(
    find.descendant(of: semantics, matching: find.byType(EditableText)),
    value,
  );
}

Finder _semantics(String label) => find.byWidgetPredicate(
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
      maxScrolls: 30,
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
    if (DateTime.now().isAfter(end)) fail('Timed out waiting for $finder');
    await tester.pump(const Duration(milliseconds: 200));
  }
  await tester.pumpAndSettle();
}

Future<void> _waitForGone(
  WidgetTester tester,
  Finder finder, {
  Duration timeout = const Duration(seconds: 25),
}) async {
  final end = DateTime.now().add(timeout);
  while (finder.evaluate().isNotEmpty) {
    if (DateTime.now().isAfter(end)) {
      fail('Timed out waiting for $finder to disappear');
    }
    await tester.pump(const Duration(milliseconds: 200));
  }
  await tester.pumpAndSettle();
}
