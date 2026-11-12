import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:settlo_core/settlo_core.dart';

/// A root page and, until it is popped, `page` above it.
Widget _stack(TargetPlatform platform, Page<void> Function() page) {
  var open = true;
  return MaterialApp(
    theme: SettloTheme.dark().copyWith(platform: platform),
    home: StatefulBuilder(
      builder: (context, setState) => Navigator(
        pages: [
          const MaterialPage<void>(
            child: Scaffold(body: Center(child: Text('Root page'))),
          ),
          if (open) page(),
        ],
        onDidRemovePage: (_) => setState(() => open = false),
      ),
    ),
  );
}

Widget _list(String title, {String? largeTitle}) => Scaffold(
  body: SettloScrollScaffold(
    title: title,
    largeTitle: largeTitle,
    previousPageTitle: 'Spaces',
    children: [
      SettloNavigationHeader(title: title),
      for (var i = 0; i < 24; i++)
        Padding(
          padding: const EdgeInsets.only(bottom: 24),
          child: Text('$title entry $i'),
        ),
    ],
  ),
);

void main() {
  for (final platform in [TargetPlatform.iOS, TargetPlatform.android]) {
    testWidgets('SettloSheetPage is a Cupertino sheet only on $platform', (
      tester,
    ) async {
      await tester.pumpWidget(
        _stack(platform, () => SettloSheetPage<void>(child: _list('Sheet'))),
      );
      await tester.pumpAndSettle();

      final route = ModalRoute.of(tester.element(find.text('Sheet entry 0')));
      final ios = platform == TargetPlatform.iOS;
      expect(
        route,
        ios ? isA<CupertinoSheetRoute<void>>() : isA<PageRoute<void>>(),
      );
      if (!ios) expect(route, isNot(isA<CupertinoSheetRoute<void>>()));
      expect(
        settloSheetTop(tester.element(find.text('Sheet entry 0'))),
        ios ? 0 : 54,
      );
    });
  }

  testWidgets('an iOS sheet drags down from its content to dismiss', (
    tester,
  ) async {
    await tester.pumpWidget(
      _stack(
        TargetPlatform.iOS,
        () => SettloSheetPage<void>(child: _list('Sheet')),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Root page'), findsOneWidget, reason: 'stays behind');

    await tester.flingFrom(
      tester.getCenter(find.text('Sheet entry 3')),
      const Offset(0, 500),
      1500,
    );
    await tester.pumpAndSettle();

    expect(find.text('Sheet entry 3'), findsNothing);
    expect(find.text('Root page'), findsOneWidget);
  });

  testWidgets('a scrolled iOS sheet scrolls back before it dismisses', (
    tester,
  ) async {
    await tester.pumpWidget(
      _stack(
        TargetPlatform.iOS,
        () => SettloSheetPage<void>(child: _list('Sheet')),
      ),
    );
    await tester.pumpAndSettle();
    await tester.drag(find.text('Sheet entry 3'), const Offset(0, -400));
    await tester.pumpAndSettle();

    await tester.drag(find.text('Sheet entry 8'), const Offset(0, 200));
    await tester.pumpAndSettle();

    expect(find.text('Sheet entry 8'), findsOneWidget, reason: 'still open');
  });

  group('detail screen navigation bar', () {
    testWidgets('iOS: large title, back titled with the previous screen, '
        'and the custom header left out', (tester) async {
      await tester.pumpWidget(
        _stack(
          TargetPlatform.iOS,
          () => SettloPage<void>(child: _list('Space', largeTitle: 'Flat 402')),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byType(CupertinoSliverNavigationBar), findsOneWidget);
      expect(find.text('Flat 402'), findsWidgets);
      expect(find.byType(SettloNavigationHeader), findsNothing);
      expect(find.text('Spaces'), findsOneWidget);

      await tester.tap(find.text('Spaces'));
      await tester.pumpAndSettle();
      expect(find.text('Root page'), findsOneWidget);
      expect(find.text('Space entry 0'), findsNothing);
    });

    testWidgets('iOS: edge swipe back pops the detail screen', (tester) async {
      await tester.pumpWidget(
        _stack(
          TargetPlatform.iOS,
          () => SettloPage<void>(child: _list('Space', largeTitle: 'Flat 402')),
        ),
      );
      await tester.pumpAndSettle();

      await tester.flingFrom(const Offset(1, 400), const Offset(600, 0), 1200);
      await tester.pumpAndSettle();

      expect(find.text('Space entry 0'), findsNothing);
      expect(find.text('Root page'), findsOneWidget);
    });

    testWidgets('Android keeps the Settlo header', (tester) async {
      await tester.pumpWidget(
        _stack(
          TargetPlatform.android,
          () => SettloPage<void>(child: _list('Space', largeTitle: 'Flat 402')),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byType(CupertinoSliverNavigationBar), findsNothing);
      expect(find.byType(SettloNavigationHeader), findsOneWidget);
      expect(find.text('Flat 402'), findsNothing);
    });
  });

  group('native confirmations', () {
    // A record, so the pending answer is not awaited by the caller's await.
    Future<(Future<bool?>,)> ask(
      WidgetTester tester,
      Future<bool?> Function(BuildContext) show,
    ) async {
      late BuildContext context;
      await tester.pumpWidget(
        MaterialApp(
          theme: SettloTheme.dark().copyWith(platform: TargetPlatform.iOS),
          home: Builder(
            builder: (c) {
              context = c;
              return const Scaffold(body: Text('Screen'));
            },
          ),
        ),
      );
      final answer = show(context);
      await tester.pumpAndSettle();
      return (answer,);
    }

    Future<bool?> sheet(BuildContext context) => showSettloActionSheet(
      context: context,
      title: 'You have 1 unsent change',
      message: 'Signing out now deletes it.',
      destructive: 'Sign Out Anyway',
      cancel: 'Keep',
    );

    Future<bool?> alert(BuildContext context) => showSettloAlert(
      context: context,
      title: 'Delete your account?',
      message: "This can't be undone.",
      destructive: 'Delete Account',
      cancel: 'Keep My Account',
    );

    for (final (name, show, yes, no) in [
      ('action sheet', sheet, 'Sign Out Anyway', 'Keep'),
      ('alert', alert, 'Delete Account', 'Keep My Account'),
    ]) {
      testWidgets('$name answers true once on a no-pump double tap', (
        tester,
      ) async {
        final (answer,) = await ask(tester, show);
        expect(
          find.byType(
            name == 'alert' ? CupertinoAlertDialog : CupertinoActionSheet,
          ),
          findsOneWidget,
        );

        await tester.tap(find.text(yes));
        await tester.tap(find.text(yes), warnIfMissed: false);
        await tester.pumpAndSettle();

        expect(await answer, isTrue);
        expect(find.text('Screen'), findsOneWidget, reason: 'one pop');
      });

      testWidgets('$name cancels with false, tinted with Settlo action', (
        tester,
      ) async {
        final (answer,) = await ask(tester, show);
        final context = tester.element(find.text(no));
        expect(
          CupertinoTheme.of(context).primaryColor,
          SettloColors.of(context).action,
          reason: 'never system blue',
        );

        await tester.tap(find.text(no));
        await tester.pumpAndSettle();

        expect(await answer, isFalse);
      });
    }
  });
}
