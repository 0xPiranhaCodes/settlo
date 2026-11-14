import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:settlo_core/settlo_core.dart';
import 'package:settlo_test_support/golden.dart';

import 'sheet_hit_test.dart' show pumpTaskGolden;

void main() {
  for (final scale in [1.0, 2.0]) {
    for (final dark in [false, true]) {
    testWidgets('repayment actions use equal full-width targets at $scale dark=$dark', (
      tester,
    ) async {
      await pumpTaskGolden(
        tester,
        GoldenDevice(name: 'se', size: const Size(375, 667), textScale: scale),
        SettloRoutes.loan('l1'),
        theme: dark ? SettloTheme.dark() : SettloTheme.light(),
      );
      final confirm = find.text('Confirm received');
      final dispute = find.text('Not received');
      await tester.scrollUntilVisible(
        confirm,
        160,
        scrollable: find.byType(Scrollable).hitTestable().last,
        maxScrolls: 40,
      );
      await tester.pumpAndSettle();
      Finder target(Finder text) =>
          find.ancestor(of: text, matching: find.byType(SPressable)).first;
      final left = tester.getRect(target(confirm));
      final right = tester.getRect(target(dispute));
      expect(left.width, closeTo(right.width, .01));
      expect(left.height, greaterThanOrEqualTo(44));
      expect(right.height, greaterThanOrEqualTo(44));
      expect(right.left - left.right, 8);
      for (final label in [confirm, dispute]) {
        final paragraph = tester.renderObject<RenderParagraph>(
          find.descendant(of: label, matching: find.byType(RichText)),
        );
        expect(paragraph.didExceedMaxLines, isFalse);
        final labelRect = tester.getRect(label);
        final targetRect = tester.getRect(target(label));
        final visiblePill = tester.getRect(
          find
              .ancestor(
                of: label,
                matching: find.byWidgetPredicate(
                  (widget) =>
                      widget is Container &&
                      widget.decoration is ShapeDecoration,
                ),
              )
              .first,
        );
        expect(visiblePill.width, closeTo(targetRect.width, .01));
        expect(visiblePill.height, greaterThanOrEqualTo(44));
        expect(targetRect.contains(labelRect.topLeft), isTrue);
        expect(labelRect.bottom, lessThanOrEqualTo(targetRect.bottom));
      }
      expect(tester.takeException(), isNull);
      await expectLater(
        find.byKey(settloGoldenSurfaceKey),
        matchesGoldenFile('goldens/phase2a_actions_${scale == 2 ? 200 : 100}_${dark ? 'dark' : 'light'}.png'),
      );
    });
    }
  }
}
