import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:settlo_core/settlo_core.dart';

void main() {
  for (final platform in [TargetPlatform.iOS, TargetPlatform.android]) {
    testWidgets('${platform.name}: task sheet header pins and closes', (
      tester,
    ) async {
      var closes = 0;
      await tester.pumpWidget(
        MaterialApp(
          theme: SettloTheme.dark().copyWith(platform: platform),
          home: Scaffold(
            body: SettloScrollScaffold(
              title: 'Edit profile',
              statusInset: 0,
              onSheetClose: () => closes++,
              children: const [
                Text('First sheet content'),
                SizedBox(height: 1800),
              ],
            ),
          ),
        ),
      );

      final header = find.byKey(const ValueKey('task-sheet-header'));
      const height = 64.0;
      expect(tester.getSize(header).height, height);
      expect(find.text('Edit profile'), findsOneWidget);
      expect(find.text('First sheet content'), findsOneWidget);
      expect(find.byKey(const ValueKey('task-sheet-grabber')), findsNothing);
      final top = tester.getTopLeft(header).dy;
      expect(closes, 0);

      await tester.drag(find.byType(CustomScrollView), const Offset(0, -400));
      await tester.pumpAndSettle();
      expect(tester.getSize(header).height, height);
      expect(tester.getTopLeft(header).dy, top);
      expect(
        tester.state<ScrollableState>(find.byType(Scrollable)).position.pixels,
        greaterThan(0),
      );

      await tester.tap(find.bySemanticsLabel('Close'));
      await tester.pumpAndSettle();
      expect(closes, 1);
      expect(tester.takeException(), isNull);
    });
  }
}
