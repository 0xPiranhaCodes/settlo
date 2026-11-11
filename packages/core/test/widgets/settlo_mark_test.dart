import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:settlo_core/settlo_core.dart';

Future<void> _pump(
  WidgetTester tester, {
  required ThemeData theme,
  String? semanticsLabel = 'Settlo',
}) => tester.pumpWidget(
  MaterialApp(
    theme: theme,
    home: Scaffold(body: SettloMark(semanticsLabel: semanticsLabel)),
  ),
);

void main() {
  testWidgets('announces Settlo and is white on the dark theme', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();
    await _pump(tester, theme: SettloTheme.dark());

    expect(find.bySemanticsLabel('Settlo'), findsOneWidget);
    expect(
      tester.widget<Image>(find.byType(Image)).color,
      SettloColors.dark.textPrimary,
    );
    semantics.dispose();
  });

  testWidgets('can be decorative and is ink on the light theme', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();
    await _pump(tester, theme: SettloTheme.light(), semanticsLabel: null);

    expect(find.bySemanticsLabel('Settlo'), findsNothing);
    expect(
      tester.widget<Image>(find.byType(Image)).color,
      SettloColors.light.textPrimary,
    );
    semantics.dispose();
  });

  testWidgets('the fallback keeps the mark', (tester) async {
    await _pump(tester, theme: SettloTheme.light());

    final image = tester.widget<Image>(find.byType(Image));
    final fallback = image.errorBuilder!(
      tester.element(find.byType(Image)),
      Exception('missing'),
      StackTrace.empty,
    );
    expect(fallback, isA<SizedBox>());
  });
}
