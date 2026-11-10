import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:settlo_core/settlo_core.dart';
import 'package:settlo_loans/settlo_loans.dart';
import 'package:settlo_test_support/golden.dart';

import 'support/fake_loans.dart';
import 'support/fake_session.dart';

/// New loan filled in as on the NewLoan artboard (n21): you lent Arjun
/// Mehta ₹10 lakh at ₹25,000 a month from March, so it ends Jul 2029.
void main() {
  for (final device in SettloGoldenDevices.accessible) {
    for (final (themeName, theme) in [
      ('dark', SettloTheme.dark()),
      ('light', SettloTheme.light()),
    ]) {
      testWidgets('${device.name} $themeName new loan golden', (tester) async {
        await pumpSettloGolden(
          tester,
          device: device,
          theme: theme,
          child: ProviderScope(
            overrides: [
              loansRepositoryProvider.overrideWithValue(
                FakeLoansRepository(loansList()),
              ),
              sessionProvider.overrideWith(
                () => FakeSessionNotifier(fakeSession),
              ),
              indiaTodayProvider.overrideWithValue(DateTime(2026, 3, 5)),
            ],
            child: ColoredBox(
              color: theme.scaffoldBackgroundColor,
              child: const NewLoanSheet(),
            ),
          ),
          act: (tester) async {
            final fields = find.byType(TextField);
            await tester.enterText(fields.at(0), '10,00,000');
            await tester.enterText(fields.at(1), '98200 11223');
            await tester.enterText(fields.at(2), 'Arjun Mehta');
            await tester.ensureVisible(find.text('Add person'));
            await tester.tap(find.text('Add person'));
            await tester.pump();
            await tester.enterText(find.byType(TextField).last, '25,000');
            FocusManager.instance.primaryFocus?.unfocus();
            await tester.drag(
              find.byType(Scrollable).first,
              const Offset(0, 2000),
            );
            await tester.pumpAndSettle();
          },
        );

        await expectLater(
          find.byKey(settloGoldenSurfaceKey),
          matchesGoldenFile('goldens/new_loan_${device.name}_$themeName.png'),
        );
      });
    }
  }
}
