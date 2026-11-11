import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:settlo_core/settlo_core.dart';

/// A root page and, until it is popped, an amount sheet holding a note
/// above it. `dirty` decides from the note, as the forms do.
Widget _app(
  TargetPlatform platform,
  TextEditingController note, {
  bool saving = false,
  ValueChanged<int>? onPopped,
}) {
  var open = true;
  var pops = 0;
  return MaterialApp(
    theme: SettloTheme.dark().copyWith(platform: platform),
    home: StatefulBuilder(
      builder: (context, setState) => Navigator(
        pages: [
          const MaterialPage<void>(
            child: Scaffold(body: Center(child: Text('Root page'))),
          ),
          if (open)
            SettloSheetPage<void>(
              child: Material(
                type: MaterialType.transparency,
                child: Builder(
                  builder: (context) => Padding(
                    padding: EdgeInsets.only(top: settloSheetTop(context)),
                    child: StatefulBuilder(
                      builder: (context, rebuild) => SAmountSheet(
                        title: 'New expense',
                        amount: const Text('0'),
                        dirty: note.text.isNotEmpty,
                        saving: saving,
                        onClose: () => Navigator.of(context).pop(),
                        body: TextField(
                          controller: note,
                          onChanged: (_) => rebuild(() {}),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
        ],
        onDidRemovePage: (_) => setState(() {
          open = false;
          onPopped?.call(++pops);
        }),
      ),
    ),
  );
}

Future<void> _type(WidgetTester tester, String text) async {
  await tester.enterText(find.byType(TextField), text);
  await tester.pump();
  FocusManager.instance.primaryFocus?.unfocus();
  await tester.pumpAndSettle();
}

Future<void> _flingFrom(WidgetTester tester, Finder from) async {
  await tester.flingFrom(tester.getCenter(from), const Offset(0, 500), 1500);
  await tester.pumpAndSettle();
}

void main() {
  final ask = find.text('Discard changes?');
  final header = find.text('New expense');
  final content = find.text('AMOUNT');

  for (final (origin, from) in [('header', header), ('content', content)]) {
    testWidgets('iOS: a drag from the $origin of a dirty sheet asks first', (
      tester,
    ) async {
      final note = TextEditingController();
      addTearDown(note.dispose);
      var pops = 0;
      await tester.pumpWidget(
        _app(TargetPlatform.iOS, note, onPopped: (n) => pops = n),
      );
      await tester.pumpAndSettle();
      await _type(tester, 'Weekly groceries');

      await _flingFrom(tester, from);
      expect(ask, findsOneWidget);
      expect(find.text('Discard'), findsOneWidget);
      await tester.tap(find.text('Keep editing'));
      await tester.pumpAndSettle();

      expect(ask, findsNothing);
      expect(note.text, 'Weekly groceries', reason: 'kept');
      expect(find.text('Weekly groceries'), findsOneWidget);
      expect(
        tester.getTopLeft(header).dy,
        lessThan(120),
        reason: 'snapped back up',
      );

      await _flingFrom(tester, from);
      await tester.tap(find.text('Discard'));
      await tester.pumpAndSettle();

      expect(header, findsNothing);
      expect(find.text('Root page'), findsOneWidget);
      expect(pops, 1, reason: 'one pop');
    });
  }

  testWidgets('iOS: Close on a dirty sheet asks; Discard closes once', (
    tester,
  ) async {
    final note = TextEditingController();
    addTearDown(note.dispose);
    var pops = 0;
    await tester.pumpWidget(
      _app(TargetPlatform.iOS, note, onPopped: (n) => pops = n),
    );
    await tester.pumpAndSettle();
    await _type(tester, '1234');

    await tester.tap(find.bySemanticsLabel('Close'));
    await tester.pumpAndSettle();
    expect(ask, findsOneWidget);
    await tester.tap(find.text('Discard'));
    await tester.tap(find.text('Discard'), warnIfMissed: false);
    await tester.pumpAndSettle();

    expect(find.text('Root page'), findsOneWidget);
    expect(pops, 1);
  });

  testWidgets('iOS: a clean sheet drags away without asking', (tester) async {
    final note = TextEditingController();
    addTearDown(note.dispose);
    await tester.pumpWidget(_app(TargetPlatform.iOS, note));
    await tester.pumpAndSettle();

    await _flingFrom(tester, content);

    expect(ask, findsNothing);
    expect(header, findsNothing);
  });

  testWidgets('iOS: a sheet saving stays put without asking', (tester) async {
    final note = TextEditingController(text: '1234');
    addTearDown(note.dispose);
    await tester.pumpWidget(_app(TargetPlatform.iOS, note, saving: true));
    await tester.pumpAndSettle();

    await _flingFrom(tester, content);
    await tester.tap(find.bySemanticsLabel('Close'));
    await tester.pumpAndSettle();

    expect(ask, findsNothing);
    expect(header, findsOneWidget);
  });

  testWidgets('Android: Close on a dirty sheet closes as before', (
    tester,
  ) async {
    final note = TextEditingController();
    addTearDown(note.dispose);
    await tester.pumpWidget(_app(TargetPlatform.android, note));
    await tester.pumpAndSettle();
    await _type(tester, '1234');

    await tester.tap(find.bySemanticsLabel('Close'));
    await tester.pumpAndSettle();

    expect(ask, findsNothing);
    expect(find.text('Root page'), findsOneWidget);
  });

  group('Reduce Motion', () {
    Future<BuildContext> reduced(WidgetTester tester) async {
      late BuildContext context;
      await tester.pumpWidget(
        MediaQuery(
          data: MediaQueryData.fromView(
            tester.view,
          ).copyWith(disableAnimations: true),
          child: MaterialApp(
            theme: SettloTheme.dark().copyWith(platform: TargetPlatform.iOS),
            home: Builder(
              builder: (c) {
                context = c;
                return const Scaffold(body: Text('Screen'));
              },
            ),
          ),
        ),
      );
      return context;
    }

    /// Where [finder] is a moment into its entrance, then once settled.
    Future<(Rect, Rect)> entrance(WidgetTester tester, Finder finder) async {
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));
      final early = tester.getRect(finder);
      await tester.pumpAndSettle();
      return (early, tester.getRect(finder));
    }

    testWidgets('an action sheet appears in place', (tester) async {
      final context = await reduced(tester);
      showSettloActionSheet(
        context: context,
        title: 'Discard changes?',
        destructive: 'Discard',
        cancel: 'Keep editing',
      ).ignore();
      final (early, settled) = await entrance(
        tester,
        find.byType(CupertinoActionSheet),
      );
      expect(early, settled);
    });

    testWidgets('an alert appears without scaling', (tester) async {
      final context = await reduced(tester);
      showSettloAlert(
        context: context,
        title: 'Delete your account?',
        message: "This can't be undone.",
        destructive: 'Delete Account',
        cancel: 'Keep',
      ).ignore();
      final (early, settled) = await entrance(
        tester,
        find.byType(CupertinoAlertDialog),
      );
      expect(early, settled);
    });

    for (final (name, page) in [
      ('task sheet', SettloSheetPage<void>.new),
      ('page', SettloPage<void>.new),
    ]) {
      testWidgets('a $name appears in place', (tester) async {
        final context = await reduced(tester);
        Navigator.of(context)
            .push(
              page(
                child: const Scaffold(body: Center(child: Text('Pushed'))),
              ).createRoute(context),
            )
            .ignore();
        final (early, settled) = await entrance(tester, find.text('Pushed'));
        expect(early, settled);
      });
    }
  });
}
