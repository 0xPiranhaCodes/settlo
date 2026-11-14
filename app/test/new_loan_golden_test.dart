import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:settlo_core/settlo_core.dart';
import 'package:settlo_core/supabase/reminders.dart';
import 'package:settlo_loans/settlo_loans.dart';
import 'package:settlo_test_support/golden.dart';

import 'support/fake_loans.dart';
import 'support/fake_reminders.dart';
import 'support/fake_session.dart';

/// New loan filled in as on the NewLoan artboard (n21): you lent Arjun
/// Mehta ₹10 lakh at ₹25,000 a month from March, so it ends Jul 2029.
void main() {
  // #158: iOS has the sliding segmented control, a Cupertino switch and
  // wheel-picker fields; Android keeps the canvas controls.
  for (final ios in [false, true]) {
    final platform = ios ? TargetPlatform.iOS : TargetPlatform.android;
    final suffix = ios ? '_ios' : '';
    for (final device
        in ios
            ? SettloGoldenDevices.all
            : [
                ...SettloGoldenDevices.accessible,
                const GoldenDevice(name: 'se375x667', size: Size(375, 667)),
                const GoldenDevice(
                  name: 'se375x667_text200',
                  size: Size(375, 667),
                  textScale: 2,
                ),
              ]) {
      for (final (themeName, theme) in [
        ('dark', SettloTheme.dark().copyWith(platform: platform)),
        ('light', SettloTheme.light().copyWith(platform: platform)),
      ]) {
        testWidgets('${device.name} $themeName new loan$suffix golden', (
          tester,
        ) async {
          await pumpSettloGolden(
            tester,
            device: device,
            theme: theme,
            child: ProviderScope(
              overrides: [
                reminderRepositoryProvider.overrideWithValue(FakeReminders()),
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
              await tester.enterText(fields.at(1), '90000 00011');
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

          if (ios && device.textScale == 1) {
            final starts = find.ancestor(
              of: find.text("Mar '26"),
              matching: find.byType(InputDecorator),
            );
            final dueDay = find.ancestor(
              of: find.text('5th'),
              matching: find.byType(InputDecorator),
            );
            expect(
              tester.getSize(starts).height,
              tester.getSize(dueDay).height,
            );
          }

          await expectLater(
            find.byKey(settloGoldenSurfaceKey),
            matchesGoldenFile(
              'goldens/new_loan${suffix}_${device.name}_$themeName.png',
            ),
          );
        });
      }
    }
  }
}
