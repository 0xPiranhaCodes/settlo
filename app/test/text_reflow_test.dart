import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:settlo_auth/settlo_auth.dart';
import 'package:settlo_core/settlo_core.dart';
import 'package:settlo_core/supabase/reminders.dart';
import 'package:settlo_loans/settlo_loans.dart';
import 'package:settlo_profile/settlo_profile.dart';
import 'package:settlo_test_support/golden.dart';

import 'support/fake_loans.dart';
import 'support/fake_profile.dart';
import 'support/fake_reminders.dart';
import 'support/fake_session.dart';

// Check actual glyph bounds as well as maxLines: fade/clip can silently lose
// text without a RenderFlex overflow or didExceedMaxLines.
void expectWholeText(WidgetTester tester, Finder finder) {
  expect(finder, findsWidgets);
  for (final element in finder.evaluate()) {
    final rich = find.descendant(
      of: find.byWidget(element.widget),
      matching: find.byType(RichText),
    );
    final paragraph = tester.renderObject<RenderParagraph>(rich.first);
    expect(paragraph.didExceedMaxLines, isFalse);
    final text = paragraph.text.toPlainText();
    for (final box in paragraph.getBoxesForSelection(
      TextSelection(baseOffset: 0, extentOffset: text.length),
    )) {
      expect(box.left, greaterThanOrEqualTo(-0.5), reason: text);
      expect(
        box.right,
        lessThanOrEqualTo(paragraph.size.width + 0.5),
        reason: text,
      );
      expect(
        box.bottom,
        lessThanOrEqualTo(paragraph.size.height + 0.5),
        reason: text,
      );
    }
  }
}

void main() {
  for (final size in [
    const Size(360, 800),
    const Size(390, 844),
    const Size(375, 667),
  ]) {
    for (final scale in [1.0, 2.0]) {
      final device = GoldenDevice(
        name: '${size.width}-$scale',
        size: size,
        textScale: scale,
      );
      for (final platform in [TargetPlatform.iOS, TargetPlatform.android]) {
        final theme = SettloTheme.light().copyWith(platform: platform);
        testWidgets(
          'Welcome layout and content reachable ${device.name} $platform',
          (tester) async {
            await pumpSettloGolden(
              tester,
              device: device,
              theme: theme,
              child: const WelcomeScreen(),
            );
            final action = find.byType(FilledButton);
            final before = tester.getRect(action);
            expect(before.top, greaterThan(0));
            if (size == const Size(390, 844) && scale == 1) {
              // Main's original composition: pinning every viewport moves
              // this down by approximately 46 points.
              expect(before.top, closeTo(683, 1));
              expect(before.height, 56);
            }
            expect(before.bottom, lessThanOrEqualTo(size.height));
            expect(action.hitTestable(), findsOneWidget);
            expectWholeText(tester, find.text('Continue with phone number'));
            if (size.width == 375 && platform == TargetPlatform.iOS) {
              await expectLater(
                find.byKey(settloGoldenSurfaceKey),
                matchesGoldenFile(
                  'goldens/reflow_welcome_se_${scale.toInt()}.png',
                ),
              );
            }
            await tester.ensureVisible(find.text('13 of 40 · on schedule'));
            await tester.pumpAndSettle();
            expect(
              find.text('13 of 40 · on schedule').hitTestable(),
              findsOneWidget,
            );
            if (size.height < 700 || scale > 1) {
              expect(tester.getRect(action), before);
            } else {
              // On taller phones the historical footer scrolls with the body.
              expect(action.hitTestable(), findsOneWidget);
            }
            expect(tester.takeException(), isNull);
          },
        );
        testWidgets('Segments reflow and select ${device.name} $platform', (
          tester,
        ) async {
          var selected = 0;
          await pumpSettloGolden(
            tester,
            device: device,
            theme: theme,
            child: Scaffold(
              body: Padding(
                padding: const EdgeInsets.all(20),
                child: StatefulBuilder(
                  builder: (context, setState) => SSegmentedControl<int>(
                    segments: const [
                      (value: 0, label: 'Equally'),
                      (value: 1, label: 'Exact'),
                      (value: 2, label: '%'),
                      (value: 3, label: 'Shares'),
                    ],
                    selected: selected,
                    onChanged: (v) => setState(() => selected = v),
                  ),
                ),
              ),
            ),
          );
          for (final label in ['Equally', 'Exact', '%', 'Shares']) {
            expectWholeText(tester, find.text(label));
            expect(find.text(label).hitTestable(), findsOneWidget);
          }
          if (scale == 2) {
            expect(
              tester.getRect(find.text('Shares')).top,
              greaterThan(tester.getRect(find.text('Equally')).bottom),
            );
          }
          if (scale == 2 && platform == TargetPlatform.iOS) {
            await expectLater(
              find.byKey(settloGoldenSurfaceKey),
              matchesGoldenFile(
                'goldens/reflow_segments_${size.width.toInt()}_200.png',
              ),
            );
          }
          await tester.tap(find.text('Shares'));
          await tester.pumpAndSettle();
          expect(selected, 3);
          expect(tester.takeException(), isNull);
        });
        for (final screen in ['detail', 'list', 'new', 'profile']) {
          testWidgets('$screen wraps complete text ${device.name} $platform', (
            tester,
          ) async {
            final container = ProviderContainer(
              overrides: [
                loansRepositoryProvider.overrideWithValue(
                  FakeLoansRepository(
                    screen == 'list'
                        ? LoansData(
                            today: DateTime(2026, 11, 13),
                            yourName: 'Sana',
                            loans: [
                              Loan(
                                id: 'fixture-phone-loan',
                                counterparty: '+919000000011',
                                youLent: true,
                                principal: const Paise.rupees(1000000),
                                repaid: Paise.zero,
                                startOn: DateTime(2026, 3, 5),
                              ),
                            ],
                          )
                        : loansList(),
                  ),
                ),
                reminderRepositoryProvider.overrideWithValue(FakeReminders()),
                sessionProvider.overrideWith(
                  () => FakeSessionNotifier(fakeSession),
                ),
                profileRepositoryProvider.overrideWithValue(
                  FakeProfileRepository(),
                ),
                themeModeRepositoryProvider.overrideWithValue(
                  FakeThemeModeRepository(ThemeMode.light),
                ),
                indiaTodayProvider.overrideWithValue(DateTime(2026, 11, 13)),
              ],
            );
            addTearDown(container.dispose);
            await container.read(loansProvider.future);
            await container.read(profileProvider.future);
            await pumpSettloGolden(
              tester,
              device: device,
              theme: theme,
              child: UncontrolledProviderScope(
                container: container,
                child: switch (screen) {
                  'detail' => const LoanDetailScreen(loanId: 'l1'),
                  'list' => const LoanScreen(),
                  'new' => const NewLoanSheet(),
                  _ => const ProfileScreen(),
                },
              ),
            );
            final target = switch (screen) {
              'detail' => find.textContaining('since Mar 2026'),
              'list' => find.text('+919000000011 · interest free'),
              'new' => find.text("Nov '26"),
              _ => find.text('Remove your profile and sign-in for good'),
            };
            await tester.scrollUntilVisible(
              target,
              200,
              scrollable: find.byType(Scrollable).first,
            );
            await tester.pumpAndSettle();
            expectWholeText(tester, target);
            expect(target.hitTestable(), findsOneWidget);
            expect(tester.takeException(), isNull);
          });
        }
      }
    }
  }
}
