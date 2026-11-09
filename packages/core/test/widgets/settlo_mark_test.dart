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
  testWidgets('announces Settlo and uses dark-theme gold', (tester) async {
    final semantics = tester.ensureSemantics();
    await _pump(tester, theme: SettloTheme.dark());

    expect(find.bySemanticsLabel('Settlo'), findsOneWidget);
    expect(
      tester.widget<Image>(find.byType(Image)).color,
      SettloColors.dark.action,
    );
    semantics.dispose();
  });

  testWidgets('can be decorative and uses light-theme ink', (tester) async {
    final semantics = tester.ensureSemantics();
    await _pump(tester, theme: SettloTheme.light(), semanticsLabel: null);

    expect(find.bySemanticsLabel('Settlo'), findsNothing);
    expect(
      tester.widget<Image>(find.byType(Image)).color,
      SettloColors.light.textPrimary,
    );
    semantics.dispose();
  });
}
