// Opt-in: flutter test test/marketing_export.dart. Never compares or writes goldens.
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:settlo/shell.dart';
import 'package:settlo_core/settlo_core.dart';
import 'package:settlo_core/supabase/reminders.dart';
import 'package:settlo_loans/settlo_loans.dart';
import 'package:settlo_settle/settlo_settle.dart';
import 'package:settlo_spaces/settlo_spaces.dart';
import 'package:settlo_test_support/golden.dart';

import 'home_golden_test.dart' show homeInShell;
import 'spaces_golden_test.dart' show spacesInShell;
import 'support/fake_expenses.dart';
import 'support/fake_home.dart';
import 'support/fake_loans.dart';
import 'support/fake_reminders.dart';
import 'support/fake_settle.dart';
import 'support/fake_spaces.dart';

void main() {
  // Preserve 390px detail crops; phones use the 430px iPhone display width.
  for (final width in [390.0, 430.0]) {
    final height = width == 430 ? 932.0 : 844.0;
    final insets = width == 430
        ? const EdgeInsets.only(top: 54, bottom: 34)
        : EdgeInsets.zero;
    for (final name in [
      'home_main',
      'settle_pay',
      'spaces_balances',
      'loans_detail',
      'confirm_repayment',
    ]) {
      testWidgets('marketing 3x $name at $width', (tester) async {
        final theme = SettloTheme.dark();
        late Widget child;
        if (name == 'home_main') {
          child = await homeInShell(homeMain);
        } else if (name == 'spaces_balances') {
          child = await spacesInShell(
            spacesList,
            SpaceScreen(spaceId: spacesList.first.id),
          );
        } else {
          final container = ProviderContainer(
            overrides: [
              if (name == 'settle_pay') ...[
                spacesRepositoryProvider.overrideWithValue(
                  FakeSpacesRepository(settleSpaces()),
                ),
                expensesRepositoryProvider.overrideWithValue(
                  FakeExpensesRepository(),
                ),
              ] else ...[
                reminderRepositoryProvider.overrideWithValue(FakeReminders()),
                loansRepositoryProvider.overrideWithValue(
                  FakeLoansRepository(loansList()),
                ),
              ],
            ],
          );
          addTearDown(container.dispose);
          if (name == 'settle_pay') {
            container.listen(settleSpacesProvider, (_, _) {});
            await container.read(settleSpacesProvider.future);
            child = ColoredBox(
              color: theme.scaffoldBackgroundColor,
              child: const SettlePayScreen(spaceId: 's2', memberId: 'm5'),
            );
          } else {
            container.listen(loansProvider, (_, _) {});
            await container.read(loansProvider.future);
            child = name == 'confirm_repayment'
                ? const ConfirmRepaymentScreen(repaymentId: 'r3')
                : SettloShell(
                    currentIndex: 2,
                    onTabSelected: (_) {},
                    child: const LoanDetailScreen(loanId: 'l1'),
                  );
          }
          child = UncontrolledProviderScope(container: container, child: child);
        }
        await pumpSettloGolden(
          tester,
          child: MediaQuery(
            data: MediaQueryData(
              size: Size(width, height),
              devicePixelRatio: 3,
              padding: insets,
              viewPadding: insets,
              disableAnimations: true,
            ),
            child: child,
          ),
          device: GoldenDevice(name: 'marketing', size: Size(width, height)),
          theme: theme,
        );
        if (width == 430 && name == 'confirm_repayment') {
          // The original 390px export cut this control off at its bottom edge.
          final button = tester.getRect(find.byType(SSecondaryButton));
          expect(button.bottom, lessThanOrEqualTo(height - insets.bottom));
          expect(button.top, greaterThanOrEqualTo(0));
        }
        // Same logical geometry, rerasterised at 3x; no PNG enlargement.
        tester.view
          ..physicalSize = Size(width * 3, height * 3)
          ..devicePixelRatio = 3;
        await tester.pump();
        expect(
          MediaQuery.devicePixelRatioOf(tester.element(find.byWidget(child))),
          3,
        );
        final boundary = tester.renderObject<RenderRepaintBoundary>(
          find.byKey(settloGoldenSurfaceKey),
        );
        await tester.runAsync(() async {
          final image = await boundary.toImage(pixelRatio: 3);
          expect(image.width, (width * 3).round());
          expect(image.height, (height * 3).round());
          final bytes = (await image.toByteData(
            format: ui.ImageByteFormat.png,
          ))!;
          final directory = Directory('../build/marketing')
            ..createSync(recursive: true);
          File('${directory.path}/$name${width == 430 ? '-phone' : ''}.png')
              .writeAsBytesSync(bytes.buffer.asUint8List());
          image.dispose();
        });
      });
    }
  }
}
