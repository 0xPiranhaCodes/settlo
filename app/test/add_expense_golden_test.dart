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
  // #158: iOS adds checkmarks, the sliding segmented control and no
  // checkboxes; Android keeps the canvas controls.
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
        testWidgets('${device.name} $themeName add expense$suffix golden', (
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
              'goldens/add_expense${suffix}_${device.name}_$themeName.png',
            ),
          );
        });
      }
    }
  }
}
