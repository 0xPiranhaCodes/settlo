import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:settlo/shell.dart';
import 'package:settlo_core/settlo_core.dart';
import 'package:settlo_core/supabase/reminders.dart';
import 'package:settlo_loans/settlo_loans.dart';
import 'package:settlo_test_support/golden.dart';

import 'support/fake_loans.dart';
import 'support/fake_reminders.dart';

/// The Loans tab and the Loan artboard (Arjun, 32% repaid, the 5 Oct
/// repayment awaiting you, n20) in the shell, dark and light.
void main() {
  for (final (state, screen) in [
    ('list', const LoanScreen()),
    ('detail', const LoanDetailScreen(loanId: 'l1')),
  ]) {
    for (final device in [
      ...SettloGoldenDevices.accessible,
      const GoldenDevice(name: 'se375x667', size: Size(375, 667)),
      const GoldenDevice(
        name: 'se375x667_text200',
        size: Size(375, 667),
        textScale: 2,
      ),
    ]) {
      for (final (themeName, theme) in [
        ('dark', SettloTheme.dark()),
        ('light', SettloTheme.light()),
      ]) {
        testWidgets('${device.name} $themeName loans $state golden', (
          tester,
        ) async {
          final container = ProviderContainer(
            overrides: [
              reminderRepositoryProvider.overrideWithValue(FakeReminders()),
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
              child: state == 'list'
                  ? SettloShell(
                      currentIndex: 2,
                      onTabSelected: (_) {},
                      child: screen,
                    )
                  : Navigator(
                      pages: [
                        MaterialPage<void>(
                          child: SettloShell(
                            currentIndex: 2,
                            onTabSelected: (_) {},
                            child: const LoanScreen(),
                          ),
                        ),
                        SettloRootSheetPage<void>(child: screen),
                      ],
                      onDidRemovePage: (_) {},
                    ),
            ),
          );

          if (state == 'list' && device.name.contains('text200')) {
            final name = find.text('Arjun · interest free');
            final paragraph = tester.renderObject<RenderParagraph>(
              find.descendant(of: name, matching: find.byType(RichText)),
            );
            expect(
              paragraph.didExceedMaxLines,
              isFalse,
              reason: 'The primary name and loan type must remain readable',
            );
          }

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

  for (final device in [
    ...SettloGoldenDevices.accessible,
    const GoldenDevice(name: 'se375x667', size: Size(375, 667)),
    const GoldenDevice(
      name: 'se375x667_text200',
      size: Size(375, 667),
      textScale: 2,
    ),
  ]) {
    for (final (themeName, theme) in [
      ('dark', SettloTheme.dark()),
      ('light', SettloTheme.light()),
    ]) {
      testWidgets('${device.name} $themeName confirm repayment golden', (
        tester,
      ) async {
        final container = ProviderContainer(
          overrides: [
            reminderRepositoryProvider.overrideWithValue(FakeReminders()),
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
