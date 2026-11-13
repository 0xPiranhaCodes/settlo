import 'dart:ui' show Tristate;

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:settlo_core/settlo_core.dart';

void main() {
  for (final theme in [SettloTheme.light(), SettloTheme.dark()]) {
    testWidgets('stacked indicator contrast ${theme.brightness}', (
      tester,
    ) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: theme,
          home: MediaQuery(
            data: const MediaQueryData(textScaler: TextScaler.linear(2)),
            child: Scaffold(
              body: SSegmentedControl<int>(
                segments: const [
                  (value: 0, label: 'Equally'),
                  (value: 1, label: 'Shares'),
                ],
                selected: 0,
                onChanged: (_) {},
              ),
            ),
          ),
        ),
      );
      final indicator = tester.widget<Icon>(
        find.byIcon(CupertinoIcons.check_mark),
      );
      final context = tester.element(find.byIcon(CupertinoIcons.check_mark));
      final colors = SettloColors.of(context);
      expect(indicator.color, colors.textPrimary);
      final foreground = indicator.color!.computeLuminance();
      final background = colors.surfaceHighest.computeLuminance();
      final contrast = (foreground > background)
          ? (foreground + .05) / (background + .05)
          : (background + .05) / (foreground + .05);
      expect(contrast, greaterThanOrEqualTo(3));
    });
  }
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
