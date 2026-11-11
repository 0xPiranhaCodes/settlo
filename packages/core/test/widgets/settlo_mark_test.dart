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

/// The artwork used as supplied, untinted (#191).
String _asset(WidgetTester tester) =>
    (tester.widget<Image>(find.byType(Image)).image as AssetImage).assetName;

void main() {
  testWidgets('announces Settlo and is the white artwork on the dark theme', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();
    await _pump(tester, theme: SettloTheme.dark());

    expect(find.bySemanticsLabel('Settlo'), findsOneWidget);
    expect(_asset(tester), 'assets/brand/settlo_mark_dark.png');
    expect(tester.widget<Image>(find.byType(Image)).color, isNull);
    semantics.dispose();
  });

  testWidgets('can be decorative and is the black artwork on the light theme', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();
    await _pump(tester, theme: SettloTheme.light(), semanticsLabel: null);

    expect(find.bySemanticsLabel('Settlo'), findsNothing);
    expect(_asset(tester), 'assets/brand/settlo_mark_light.png');
    expect(tester.widget<Image>(find.byType(Image)).color, isNull);
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
