import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:settlo/main.dart' as app;
import 'package:settlo_auth/settlo_auth.dart';
import 'package:settlo_balances/settlo_balances.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Signs in with a fixed test number against the local Supabase stack
/// (`supabase/config.local-dev.toml`). Needs a device and the stack's
/// settings; see app/README.md › Integration test.
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  /// Pumps until [finder] finds something, for steps that wait on the
  /// network.
  Future<void> pumpUntilFound(WidgetTester tester, Finder finder) async {
    final end = DateTime.now().add(const Duration(seconds: 20));
    while (finder.evaluate().isEmpty) {
      if (DateTime.now().isAfter(end)) {
        fail('Timed out waiting for $finder');
      }
      await tester.pump(const Duration(milliseconds: 200));
    }
    await tester.pumpAndSettle();
  }

  testWidgets('signs in with +91 90000 00001 and code 123456', (tester) async {
    await app.main();
    // A session kept from an earlier run would skip sign-in.
    await Supabase.instance.client.auth.signOut();
    addTearDown(Supabase.instance.client.auth.signOut);
    await pumpUntilFound(tester, find.byType(WelcomeScreen));

    await tester.tap(find.text('Continue with phone number'));
    await pumpUntilFound(tester, find.byType(PhoneScreen));
    await tester.enterText(
      find.byKey(const ValueKey('phone-number')),
      '9000000001',
    );
    await tester.tap(find.text('Send code'));
    await pumpUntilFound(tester, find.byType(OtpScreen));

    await tester.enterText(find.byKey(const ValueKey('otp-code')), '123456');
    await pumpUntilFound(tester, find.byType(HomeScreen));

    final user = Supabase.instance.client.auth.currentUser;
    expect(user?.phone, '919000000001');
  });
}
