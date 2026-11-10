import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:settlo_core/settlo_core.dart';
import 'package:settlo_test_support/golden.dart';

void main() {
  test('app and feature code use named type roles, never raw sizes', () {
    final failures = <String>[];
    for (final root in [Directory('lib'), Directory('../packages/features')]) {
      for (final file in root.listSync(recursive: true).whereType<File>()) {
        if (!file.path.endsWith('.dart') || file.path.contains('/test/')) {
          continue;
        }
        if (RegExp(r'SettloTypography\.figtree\s*\(|fontSize\s*:')
            .hasMatch(file.readAsStringSync())) {
          failures.add(file.path);
        }
      }
    }
    expect(failures, isEmpty);
  });

  test(
    'core raw sizing is limited to named roles, PDF and derived symbols',
    () {
      const allowed = {
        '../packages/core/lib/widgets/amount_sheet.dart': 1,
        '../packages/core/lib/widgets/money_text.dart': 1,
        '../packages/core/lib/widgets/avatar.dart': 1,
      };
      final seen = <String, int>{};
      for (final file in Directory(
        '../packages/core/lib',
      ).listSync(recursive: true).whereType<File>()) {
        if (!file.path.endsWith('.dart') ||
            file.path.endsWith('/theme/typography.dart') ||
            file.path.endsWith('/export/statements.dart')) {
          continue;
        }
        final source = file.readAsStringSync();
        expect(
          RegExp(r'fontSize\s*:').hasMatch(source),
          isFalse,
          reason: file.path,
        );
        final count = RegExp(r'SettloTypography\.figtree\s*\(')
            .allMatches(source)
            .length;
        if (count > 0) seen[file.path] = count;
      }
      expect(seen, allowed);
    },
  );

  test('named roles map to the platform ramp', () {
    final theme = SettloTypography.textTheme(Colors.black);
    expect(
      [
        theme.displayLarge!.fontSize,
        theme.headlineMedium!.fontSize,
        theme.headlineSmall!.fontSize,
        theme.titleLarge!.fontSize,
        theme.titleMedium!.fontSize,
        theme.bodyLarge!.fontSize,
        theme.labelLarge!.fontSize,
        theme.bodySmall!.fontSize,
        theme.labelMedium!.fontSize,
        SettloTypography.caption1().fontSize,
        theme.labelSmall!.fontSize,
      ],
      [34, 28, 22, 20, 17, 17, 16, 15, 13, 12, 11],
    );
    expect(theme.labelLarge!.fontWeight, FontWeight.w600);
  });

  testWidgets('word audit rejects a word broken over two lines', (
    tester,
  ) async {
    await loadSettloFonts();
    await tester.pumpWidget(
      MaterialApp(
        home: Center(
          child: SizedBox(
            width: 38,
            child: Text('Schedule', style: SettloTypography.body()),
          ),
        ),
      ),
    );
    expect(() => expectNoMidWordBreaks(tester), throwsA(isA<TestFailure>()));
  });

  testWidgets('minimum type audit rejects 11pt outside navigation', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Text('Too small', style: TextStyle(fontSize: 11)),
      ),
    );
    expect(() => expectSettloTypeMinimum(tester), throwsA(isA<TestFailure>()));
  });
}
