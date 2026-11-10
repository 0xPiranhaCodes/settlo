import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:settlo/main.dart' as app;
import 'package:settlo_auth/settlo_auth.dart';
import 'package:settlo_balances/settlo_balances.dart';
import 'package:settlo_expenses/settlo_expenses.dart';
import 'package:settlo_local/settlo_local.dart';
import 'package:settlo_spaces/settlo_spaces.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Whether the app's network is cut: every request goes to a dead proxy and
/// fails to connect, as with no signal.
var _offline = false;

final class _Network extends HttpOverrides {
  @override
  HttpClient createHttpClient(SecurityContext? context) =>
      super.createHttpClient(context)
        ..findProxy = (_) => _offline ? 'PROXY 127.0.0.1:9' : 'DIRECT';
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('an expense added offline syncs once on reconnect', (
    tester,
  ) async {
    HttpOverrides.global = _Network();
    await app.main();
    await Supabase.instance.client.auth.signOut();
    addTearDown(Supabase.instance.client.auth.signOut);
    await _waitFor(tester, find.byType(WelcomeScreen));

    await _signIn(tester, phone: '9000000001');
    final me = Supabase.instance.client.auth.currentUser!.id;
    final name = 'Offline flat ${DateTime.now().millisecondsSinceEpoch}';
    await tester.tap(find.text('Spaces').last);
    await _waitFor(tester, find.byType(SpacesListScreen));
    await _createSpace(tester, name);
    await tester.tap(find.text(name));
    await _waitFor(tester, find.text('Add first expense'));

    // No signal: the expense is queued and shown from the queue.
    _offline = true;
    await tester.tap(find.text('Add first expense'));
    await _waitFor(tester, find.byType(AddExpenseSheet));
    await _enterLabeled(tester, 'Amount in rupees', '90.00');
    await _enterLabeled(tester, 'What for', 'Offline groceries');
    await _scrollTo(tester, find.text('Save expense'));
    await tester.tap(find.text('Save expense'));
    await _waitFor(tester, find.text('Offline groceries'));

    final container = ProviderScope.containerOf(
      tester.element(find.byType(app.SettloApp)),
    );
    final db = container.read(localDbProvider);
    final queued = await db.mutations(me);
    expect([for (final m in queued) (m.kind, m.applied)], [
      ('add_expense', false),
    ]);
    expect(queued.single.attempts, greaterThan(0));
    await _scrollTo(tester, find.text('Balances'));
    await tester.tap(find.text('Balances'));
    await _waitFor(tester, find.text('YOU ARE OWED'));
    await _scrollTo(tester, find.text('paid ₹90 · '));

    // Signal back: the backoff retry replays the queued write with its key,
    // then the mirror refreshes from the server.
    _offline = false;
    final end = DateTime.now().add(const Duration(seconds: 90));
    while ((await db.mutations(me)).isNotEmpty) {
      if (DateTime.now().isAfter(end)) fail('the queue never drained');
      await tester.pump(const Duration(milliseconds: 500));
    }
    await tester.pumpAndSettle();

    // The server counted it exactly once: one expense, balances +60/-30/-30.
    final db_ = Supabase.instance.client;
    final space = await db_
        .from('spaces')
        .select('id')
        .eq('name', name)
        .single();
    final expenses = await db_
        .from('expenses')
        .select('id, amount_minor')
        .eq('space_id', space['id'] as String);
    expect(expenses, [
      {'id': expenses.single['id'], 'amount_minor': 9000},
    ]);
    final balances = await db_
        .from('space_member_balances')
        .select('user_id, balance_minor')
        .eq('space_id', space['id'] as String);
    expect(
      {for (final b in balances) b['user_id'] ?? 'pending': b['balance_minor']},
      {me: 6000, 'pending': -3000},
    );
    expect(balances, hasLength(3));

    // And the app shows the server's numbers, not the queue's twice over.
    final mirror = await db.mirror(me);
    expect([
      for (final e in mirror['expenses']!)
        if (e['space_id'] == space['id']) e['amount_minor'],
    ], [9000]);
    // The refresh reloads the space, which opens on its Expenses tab.
    await _scrollTo(tester, find.text('Balances'));
    await tester.tap(find.text('Balances'));
    await _waitFor(tester, find.text('paid ₹90 · '));
    expect(find.text('paid ₹0 · '), findsNWidgets(2));
    debugPrint('offline expense converged: ${expenses.single['id']}');
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

Future<void> _createSpace(WidgetTester tester, String name) async {
  await tester.tap(find.byTooltip('New space'));
  await _waitFor(tester, find.byType(CreateSpaceSheet));
  final fields = find.descendant(
    of: find.byType(CreateSpaceSheet),
    matching: find.byType(TextField),
  );
  await tester.enterText(fields.at(0), name);
  await tester.enterText(fields.at(1), '9000000002');
  await tester.enterText(fields.at(2), 'Bela');
  await tester.tap(find.text('Add person'));
  await tester.enterText(fields.at(1), '9000000003');
  await tester.enterText(fields.at(2), 'Charu');
  await tester.tap(find.text('Add person'));
  await _scrollTo(tester, find.text('Create space'));
  await tester.tap(find.text('Create space'));
  await _waitFor(tester, find.text(name));
}

Future<void> _enterLabeled(
  WidgetTester tester,
  String label,
  String value,
) async {
  final semantics = find.byWidgetPredicate(
    (widget) => widget is Semantics && widget.properties.label == label,
    description: 'Semantics(label: $label)',
  );
  await _scrollTo(tester, semantics);
  await tester.enterText(
    find.descendant(of: semantics, matching: find.byType(EditableText)),
    value,
  );
}

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
    if (DateTime.now().isAfter(end)) fail('Timed out waiting for $finder');
    await tester.pump(const Duration(milliseconds: 200));
  }
  await tester.pumpAndSettle();
}
