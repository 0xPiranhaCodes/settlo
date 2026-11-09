import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:settlo/shell.dart';
import 'package:settlo_core/settlo_core.dart';
import 'package:settlo_loans/settlo_loans.dart';
import 'package:settlo_test_support/golden.dart';

import 'support/fake_loans.dart';

/// The Loans tab and the Loan artboard (Arjun, 32% repaid, the 5 Oct
/// repayment awaiting you, n20) in the shell, dark and light.
void main() {
  for (final (state, screen) in [
    ('list', const LoanScreen()),
    ('detail', const LoanDetailScreen(loanId: 'l1')),
  ]) {
    for (final device in SettloGoldenDevices.all) {
      for (final (themeName, theme) in [
        ('dark', SettloTheme.dark()),
        ('light', SettloTheme.light()),
      ]) {
        testWidgets('${device.name} $themeName loans $state golden', (
          tester,
        ) async {
          final container = ProviderContainer(
            overrides: [
              loansRepositoryProvider.overrideWithValue(
                FakeLoansRepository(loansList()),
              ),
            ],
          );
          addTearDown(container.dispose);
          container.listen(loansProvider, (_, _) {});
          await container.read(loansProvider.future);

          await pumpSettloGolden(
            tester,
            device: device,
            theme: theme,
            child: UncontrolledProviderScope(
              container: container,
              child: SettloShell(
                currentIndex: 2,
                onTabSelected: (_) {},
                child: screen,
              ),
            ),
          );

          await expectLater(
            find.byKey(settloGoldenSurfaceKey),
            matchesGoldenFile(
              'goldens/loans_${state}_${device.name}_$themeName.png',
            ),
          );
        });
      }
    }
  }

  for (final device in SettloGoldenDevices.all) {
    for (final (themeName, theme) in [
      ('dark', SettloTheme.dark()),
      ('light', SettloTheme.light()),
    ]) {
      testWidgets('${device.name} $themeName confirm repayment golden', (
        tester,
      ) async {
        final container = ProviderContainer(
          overrides: [
            loansRepositoryProvider.overrideWithValue(
              FakeLoansRepository(loansList()),
            ),
          ],
        );
        addTearDown(container.dispose);
        container.listen(loansProvider, (_, _) {});
        await container.read(loansProvider.future);

        await pumpSettloGolden(
          tester,
          device: device,
          theme: theme,
          child: UncontrolledProviderScope(
            container: container,
            child: const ConfirmRepaymentScreen(repaymentId: 'r3'),
          ),
        );

        await expectLater(
          find.byKey(settloGoldenSurfaceKey),
          matchesGoldenFile(
            'goldens/confirm_repayment_${device.name}_$themeName.png',
          ),
        );
      });
    }
  }
}
