import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:settlo_core/settlo_core.dart';

Future<void> _pump(
  WidgetTester tester, {
  required ThemeData theme,
  String? semanticsLabel = 'Settlo',
  Color? color,
}) => tester.pumpWidget(
  MaterialApp(
    theme: theme,
    home: Scaffold(
      body: SettloMark(semanticsLabel: semanticsLabel, color: color),
    ),
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

  testWidgets('a composition can supply gold and the fallback keeps the mark', (
    tester,
  ) async {
    const gold = Color(0xFFF2C77F);
    await _pump(tester, theme: SettloTheme.light(), color: gold);

    final image = tester.widget<Image>(find.byType(Image));
    expect(image.color, gold);
    final fallback = image.errorBuilder!(
      tester.element(find.byType(Image)),
      Exception('missing'),
      StackTrace.empty,
    );
    expect(fallback, isA<SizedBox>());
  });
}
