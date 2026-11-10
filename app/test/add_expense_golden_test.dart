import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:settlo_core/settlo_core.dart';
import 'package:settlo_expenses/settlo_expenses.dart';
import 'package:settlo_test_support/golden.dart';

import 'support/fake_expenses.dart';
import 'support/fake_spaces.dart';

/// Add expense in Flat 402 filled in as on the AddExpense artboard:
/// ₹1,800 of groceries, you paid, split equally three ways.
void main() {
  for (final device in SettloGoldenDevices.accessible) {
    for (final (themeName, theme) in [
      ('dark', SettloTheme.dark()),
      ('light', SettloTheme.light()),
    ]) {
      testWidgets('${device.name} $themeName add expense golden', (
        tester,
      ) async {
        final container = ProviderContainer(
          overrides: [
            spacesRepositoryProvider.overrideWithValue(
              FakeSpacesRepository([spacesList.first]),
            ),
            expensesRepositoryProvider.overrideWithValue(
              FakeExpensesRepository(),
            ),
          ],
        );
        addTearDown(container.dispose);
        container.listen(expenseSpacesProvider, (_, _) {});
        await container.read(expenseSpacesProvider.future);

        await pumpSettloGolden(
          tester,
          device: device,
          theme: theme,
          child: UncontrolledProviderScope(
            container: container,
            child: ColoredBox(
              color: theme.scaffoldBackgroundColor,
              child: AddExpenseScreen(spaceId: spacesList.first.id),
            ),
          ),
          act: (tester) async {
            final fields = find.byType(TextField);
            await tester.enterText(fields.at(0), '1800');
            await tester.enterText(fields.at(1), 'Groceries · BigBasket');
            await tester.tap(find.text('Groceries'));
            FocusManager.instance.primaryFocus?.unfocus();
          },
        );

        if (device.name.contains('text200')) {
          for (final name in ['Rahul', 'Priya']) {
            final paragraphs = tester.renderObjectList<RenderParagraph>(
              find.descendant(
                of: find.text(name),
                matching: find.byType(RichText),
              ),
            );
            expect(paragraphs, isNotEmpty);
            for (final paragraph in paragraphs) {
              expect(paragraph.didExceedMaxLines, isFalse);
            }
          }
        }

        await expectLater(
          find.byKey(settloGoldenSurfaceKey),
          matchesGoldenFile(
            'goldens/add_expense_${device.name}_$themeName.png',
          ),
        );
      });
    }
  }
}
