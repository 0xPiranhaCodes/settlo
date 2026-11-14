import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:settlo_core/settlo_core.dart';

/// A root page and, until it is popped, a navigator sheet whose first page
/// pushes a second inside it.
Widget _app(TargetPlatform platform, {bool reduced = false}) {
  var open = true;
  return MaterialApp(
    theme: SettloTheme.dark().copyWith(platform: platform),
    home: MediaQuery(
      data: MediaQueryData(disableAnimations: reduced),
      child: StatefulBuilder(
        builder: (context, setState) => Navigator(
          pages: [
            const MaterialPage<void>(
              child: Scaffold(body: Center(child: Text('Root page'))),
            ),
            if (open)
              SettloNavigatorSheetPage<void>(
                child: Scaffold(
                  body: ListView(
                    children: [
                      const SizedBox(height: 80),
                      Builder(
                        builder: (context) => TextButton(
                          onPressed: () => Navigator.of(context).push(
                            settloPageRoute<void>(
                              context,
                              (_) => const Scaffold(
                                body: Center(child: Text('Pushed page')),
                              ),
                            ),
                          ),
                          child: const Text('First page'),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
          ],
          onDidRemovePage: (_) => setState(() => open = false),
        ),
      ),
    ),
  );
}

/// Back on the navigator that holds the sheet, as the router's would be.
Future<void> _back(WidgetTester tester) async {
  await tester
      .state<NavigatorState>(
        find
            .ancestor(
              of: find.text('Root page', skipOffstage: false),
              matching: find.byType(Navigator),
            )
            .first,
      )
      .maybePop();
  await tester.pumpAndSettle();
}

void main() {
  for (final platform in [TargetPlatform.iOS, TargetPlatform.android]) {
    testWidgets('${platform.name}: Back pops the pushed page, then the sheet', (
      tester,
    ) async {
      await tester.pumpWidget(_app(platform));
      await tester.pumpAndSettle();
      await tester.tap(find.text('First page'));
      await tester.pumpAndSettle();
      expect(find.text('Pushed page'), findsOneWidget);

      await _back(tester);
      expect(find.text('Pushed page'), findsNothing);
      expect(find.text('First page'), findsOneWidget);

      await _back(tester);
      expect(find.text('First page'), findsNothing);
      expect(find.text('Root page'), findsOneWidget);
    });
  }

  testWidgets('android: the sheet has no drag handle and opens with reduced '
      'motion', (tester) async {
    await tester.pumpWidget(_app(TargetPlatform.android, reduced: true));
    await tester.pump();
    expect(find.text('First page'), findsOneWidget);
    expect(
      find.byWidgetPredicate(
        (w) => w is BottomSheet && !(w.showDragHandle ?? false),
      ),
      findsOneWidget,
    );
  });

  testWidgets('iOS: a drag down with a page pushed closes the whole sheet', (
    tester,
  ) async {
    await tester.pumpWidget(_app(TargetPlatform.iOS));
    await tester.pumpAndSettle();
    await tester.tap(find.text('First page'));
    await tester.pumpAndSettle();

    await tester.flingFrom(
      tester.getCenter(find.text('Pushed page')),
      const Offset(0, 500),
      1500,
    );
    await tester.pumpAndSettle();

    expect(find.text('Pushed page'), findsNothing);
    expect(find.text('First page'), findsNothing);
    expect(find.text('Root page'), findsOneWidget);
  });
}
