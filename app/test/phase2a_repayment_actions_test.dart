import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:settlo_core/settlo_core.dart';
import 'package:settlo_test_support/golden.dart';

import 'sheet_hit_test.dart' show pumpTaskGolden;

void main() {
  for (final scale in [1.0, 2.0]) {
    testWidgets('repayment actions use equal full-width targets at $scale', (
      tester,
    ) async {
      await pumpTaskGolden(
        tester,
        GoldenDevice(name: 'se', size: const Size(375, 667), textScale: scale),
        SettloRoutes.loan('l1'),
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
        expect(targetRect.contains(labelRect.topLeft), isTrue);
        expect(labelRect.bottom, lessThanOrEqualTo(targetRect.bottom));
      }
      expect(tester.takeException(), isNull);
    });
  }
}
