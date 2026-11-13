import 'dart:ui' show Tristate;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:settlo_core/settlo_core.dart';

void main() {
  for (final platform in [TargetPlatform.iOS, TargetPlatform.android]) {
    testWidgets('large segments keep full targets and selection on $platform', (
      tester,
    ) async {
      final semantics = tester.ensureSemantics();
      var selected = 0;
      await tester.pumpWidget(
        MaterialApp(
          theme: SettloTheme.light().copyWith(platform: platform),
          home: MediaQuery(
            data: const MediaQueryData(textScaler: TextScaler.linear(2)),
            child: Scaffold(
              body: SizedBox(
                width: 320,
                child: StatefulBuilder(
                  builder: (context, setState) => SSegmentedControl<int>(
                    segments: const [
                      (value: 0, label: 'Equally'),
                      (value: 1, label: 'Shares'),
                    ],
                    selected: selected,
                    onChanged: (value) => setState(() => selected = value),
                  ),
                ),
              ),
            ),
          ),
        ),
      );
      expect(
        tester.getTopLeft(find.text('Shares')).dy,
        greaterThan(tester.getBottomLeft(find.text('Equally')).dy),
      );
      final targets = find.byType(SPressable);
      expect(targets, findsNWidgets(2));
      for (final target in targets.evaluate()) {
        final size = tester.getSize(find.byWidget(target.widget));
        expect(size.width, 320);
        expect(size.height, greaterThanOrEqualTo(44));
      }
      await tester.tapAt(tester.getTopLeft(targets.last) + const Offset(2, 2));
      await tester.pumpAndSettle();
      expect(selected, 1);
      expect(
        tester.getSemantics(find.text('Shares')).flagsCollection.isSelected,
        Tristate.isTrue,
      );
      expect(tester.takeException(), isNull);
      semantics.dispose();
    });
  }
}
