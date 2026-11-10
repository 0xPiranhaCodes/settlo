import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:settlo_core/settlo_core.dart';
import 'package:settlo_test_support/golden.dart';

void main() {
  testWidgets(
    'tree audit rejects small raw controls, accepts shared controls',
    (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: SettloTheme.dark(),
          home: Center(
            child: GestureDetector(
              onTap: () {},
              child: const SizedBox.square(dimension: 24),
            ),
          ),
        ),
      );
      expect(() => expectSettloTapTargets(tester), throwsA(isA<TestFailure>()));
      await tester.pumpWidget(
        MaterialApp(
          theme: SettloTheme.dark(),
          home: Center(
            child: SPressable(
              onTap: () {},
              child: const SizedBox.square(dimension: 24),
            ),
          ),
        ),
      );
      expectSettloTapTargets(tester);
    },
  );
}
