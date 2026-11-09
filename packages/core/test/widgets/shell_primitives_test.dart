import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:settlo_core/settlo_core.dart';

void main() {
  testWidgets('placeholder names its screen and artboard', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: SettloTheme.dark(),
        home: const SPlaceholderScreen(title: 'Spaces', artboard: 'SpacesList'),
      ),
    );
    expect(find.text('Spaces'), findsOneWidget);
    expect(find.textContaining('SpacesList'), findsOneWidget);
  });

  testWidgets('tab icons paint at the icon theme size and colour', (
    tester,
  ) async {
    await tester.pumpWidget(
      IconTheme(
        data: const IconThemeData(size: 22, color: Color(0xFFF3F2EE)),
        child: Row(
          textDirection: TextDirection.ltr,
          children: [for (final icon in STabIcon.values) icon.widget],
        ),
      ),
    );
    final paints = find.descendant(
      of: find.byType(Row),
      matching: find.byType(CustomPaint),
    );
    expect(paints, findsNWidgets(STabIcon.values.length));
    for (final paint in tester.widgetList<CustomPaint>(paints)) {
      expect(paint.size, const Size.square(22));
      expect(paint.painter!.shouldRepaint(paint.painter!), isFalse);
    }
  });
}
