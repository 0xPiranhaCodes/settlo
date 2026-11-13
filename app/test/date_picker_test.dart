import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:settlo_core/settlo_core.dart';
import 'package:settlo_core/supabase/reminders.dart';
import 'package:settlo_expenses/settlo_expenses.dart';
import 'package:settlo_loans/settlo_loans.dart';
import 'package:settlo_loans/src/record_repayment_sheet.dart';

import 'support/fake_expenses.dart';
import 'support/fake_loans.dart';
import 'support/fake_reminders.dart';
import 'support/fake_session.dart';
import 'support/fake_spaces.dart';

void main() {
  for (final light in [false, true]) {
    for (final flow in ['expense', 'repayment', 'loan']) {
      testWidgets('$flow date wheel is readable ${light ? 'light' : 'dark'}', (
        tester,
      ) async {
        final semantics = tester.ensureSemantics();
        tester.view.physicalSize = const Size(390, 844);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        await tester.pumpWidget(
          ProviderScope(
            overrides: [
              indiaTodayProvider.overrideWithValue(DateTime(2026, 11, 10)),
              sessionProvider.overrideWith(
                () => FakeSessionNotifier(fakeSession),
              ),
              reminderRepositoryProvider.overrideWithValue(FakeReminders()),
              loansRepositoryProvider.overrideWithValue(
                FakeLoansRepository(loansList()),
              ),
              expensesRepositoryProvider.overrideWithValue(
                FakeExpensesRepository(),
              ),
              spacesRepositoryProvider.overrideWithValue(
                FakeSpacesRepository([spacesList.first]),
              ),
            ],
            child: MaterialApp(
              theme: (light ? SettloTheme.light() : SettloTheme.dark())
                  .copyWith(platform: TargetPlatform.iOS),
              home: Scaffold(
                body: switch (flow) {
                  'expense' => AddExpenseScreen(spaceId: spacesList.first.id),
                  'repayment' => RecordRepaymentSheet(
                    loan: arjunLoan(),
                    onClose: () {},
                  ),
                  _ => const NewLoanSheet(),
                },
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        final trigger = flow == 'loan'
            ? find.bySemanticsLabel(RegExp('Starts '))
            : find.text('Today');
        await tester.ensureVisible(trigger);
        await tester.tap(trigger);
        await tester.pumpAndSettle();
        expect(find.byType(CupertinoDatePicker), findsOneWidget);
        final bands = tester.widgetList<CupertinoPickerDefaultSelectionOverlay>(
          find.byType(CupertinoPickerDefaultSelectionOverlay),
        );
        expect(bands, hasLength(3));
        for (final band in bands) {
          expect(band.background.a, lessThanOrEqualTo(0.35));
        }
        final picker = tester.widget<CupertinoDatePicker>(
          find.byType(CupertinoDatePicker),
        );
        final previous = picker.initialDateTime.subtract(
          const Duration(days: 1),
        );
        // Exercise the real wheel and commit the changed value to the form.
        await tester.drag(
          find.text('${picker.initialDateTime.day}').last,
          const Offset(0, 40),
        );
        await tester.pumpAndSettle();
        await tester.tap(find.text('Done'));
        await tester.pumpAndSettle();
        expect(find.byType(CupertinoDatePicker), findsNothing);
        if (flow == 'loan') {
          expect(
            find.bySemanticsLabel(RegExp('Starts ${previous.day} ')),
            findsOneWidget,
          );
        } else {
          expect(find.textContaining('${previous.day} '), findsWidgets);
        }
        semantics.dispose();
      });
    }
  }
}
