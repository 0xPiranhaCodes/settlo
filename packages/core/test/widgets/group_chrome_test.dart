import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:settlo_core/settlo_core.dart';
import 'package:settlo_test_support/golden.dart';

void main() {
  for (final height in [52.0, 62.0, 64.0]) {
    testWidgets('legacy frame $height preserves the 44pt close target', (
      tester,
    ) async {
      final semantics = tester.ensureSemantics();
      await tester.pumpWidget(
        MaterialApp(
          theme: SettloTheme.light(),
          home: Scaffold(
            body: SizedBox(
              height: height,
              child: SSheetHeader(title: 'New loan', onClose: () {}),
            ),
          ),
        ),
      );
      try {
        await expectLater(tester, meetsGuideline(iOSTapTargetGuideline));
        expect(tester.takeException(), isNull);
      } finally {
        semantics.dispose();
      }
    });
  }
  testWidgets('group action and section labels remain accessible', (
    tester,
  ) async {
    var taps = 0;
    await tester.pumpWidget(
      MaterialApp(
        theme: SettloTheme.light(),
        home: Scaffold(
          body: Column(
            children: [
              SSectionLabel('November'.toLowerCase()),
              SGroup(
                children: [
                  SRow(title: 'Rent', onTap: () => taps++, separator: false),
                ],
              ),
            ],
          ),
        ),
      ),
    );
    expect(find.text('NOVEMBER'), findsOneWidget);
    await tester.tap(find.text('Rent'));
    expect(taps, 1);
  });
  testWidgets('pull to refresh keeps the header flat above the content', (
    tester,
  ) async {
    var refreshes = 0;
    await tester.pumpWidget(
      MaterialApp(
        theme: SettloTheme.light(),
        home: SSheetScaffold(
          title: 'Flat 402',
          onClose: () {},
          onRefresh: () async {
            refreshes++;
          },
          children: const [Text('Ledger'), SizedBox(height: 1500)],
        ),
      ),
    );
    await tester.drag(find.byType(CustomScrollView), const Offset(0, 400));
    await tester.pumpAndSettle();
    expect(refreshes, 1);
    expect(
      tester.widget<SSheetHeader>(find.byType(SSheetHeader)).scrolledUnder,
      isFalse,
    );
  });
  for (final platform in [TargetPlatform.iOS, TargetPlatform.android]) {
    testWidgets('routed sheet updates segments in place on $platform', (
      tester,
    ) async {
      var title = 'Expenses';
      late StateSetter update;
      await tester.pumpWidget(
        MaterialApp(
          theme: SettloTheme.light().copyWith(platform: platform),
          home: MediaQuery(
            data: const MediaQueryData(disableAnimations: true),
            child: StatefulBuilder(
              builder: (context, setState) {
                update = setState;
                return Navigator(
                  pages: [
                    const MaterialPage<void>(
                      child: Scaffold(body: Text('Tabs')),
                    ),
                    SettloRootSheetPage<void>(
                      key: const ValueKey('space'),
                      child: SSheetScaffold(
                        title: title,
                        onClose: () {},
                        leading: const Icon(Icons.home),
                        onTitlePressed: () => update(() => title = 'Members'),
                        titleActionLabel: 'Members',
                        children: const [Text('Ledger')],
                      ),
                    ),
                  ],
                  onDidRemovePage: (_) {},
                );
              },
            ),
          ),
        ),
      );
      final route = ModalRoute.of(tester.element(find.byType(SSheetHeader)));
      update(() => title = 'Balances');
      await tester.pumpAndSettle();
      expect(find.text('Balances'), findsOneWidget);
      expect(
        ModalRoute.of(tester.element(find.byType(SSheetHeader))),
        same(route),
      );
      await tester.tap(find.bySemanticsLabel('Members'));
      await tester.pumpAndSettle();
      expect(find.text('Members'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }

  for (final platform in [TargetPlatform.iOS, TargetPlatform.android]) {
    testWidgets('imperative sheet uses root navigator on $platform', (
      tester,
    ) async {
      final root = GlobalKey<NavigatorState>();
      final nested = GlobalKey<NavigatorState>();
      await tester.pumpWidget(
        MaterialApp(
          navigatorKey: root,
          theme: SettloTheme.light().copyWith(platform: platform),
          home: Navigator(
            key: nested,
            onGenerateRoute: (_) => MaterialPageRoute<void>(
              builder: (context) => Scaffold(
                body: TextButton(
                  child: const Text('Open'),
                  onPressed: () => pushSettloSheet<void>(
                    context,
                    (context) => SSheetScaffold(
                      title: 'Sheet',
                      onClose: () => Navigator.pop(context),
                      children: const [Text('Body')],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();
      expect(root.currentState!.canPop(), isTrue);
      expect(nested.currentState!.canPop(), isFalse);
      await tester.tap(find.bySemanticsLabel('Close'));
      await tester.pumpAndSettle();
      expect(root.currentState!.canPop(), isFalse);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('sheet is flat at rest, blurred under scroll, and closes', (
    tester,
  ) async {
    var closes = 0;
    await tester.pumpWidget(
      MaterialApp(
        theme: SettloTheme.light(),
        home: SSheetScaffold(
          title: 'Flat 402',
          onClose: () => closes++,
          children: const [Text('First content'), SizedBox(height: 1500)],
        ),
      ),
    );
    final header = find.byType(SSheetHeader);
    final filter = find.descendant(
      of: header,
      matching: find.byType(BackdropFilter),
    );
    expect(tester.getSize(header).height, 64);
    expect(
      tester.getTopLeft(find.text('First content')).dy -
          tester.getBottomLeft(header).dy,
      16,
    );
    expect(tester.widget<BackdropFilter>(filter).enabled, isFalse);
    final top = tester.getTopLeft(header);
    await tester.drag(find.byType(CustomScrollView), const Offset(0, -200));
    await tester.pumpAndSettle();
    expect(tester.getTopLeft(header), top);
    expect(tester.widget<BackdropFilter>(filter).enabled, isTrue);
    final background = tester.widget<ColoredBox>(
      find.descendant(of: header, matching: find.byType(ColoredBox)).first,
    );
    expect(background.color.a, closeTo(.8, .01));
    await tester.drag(find.byType(CustomScrollView), const Offset(0, 400));
    await tester.pumpAndSettle();
    expect(tester.widget<BackdropFilter>(filter).enabled, isFalse);
    await tester.tap(find.bySemanticsLabel('Close'));
    expect(closes, 1);
    expect(tester.takeException(), isNull);
  });
  for (final scale in [1.0, 2.0]) {
    testWidgets('row geometry and wrapping at $scale', (tester) async {
      await loadSettloFonts();
      await tester.binding.setSurfaceSize(const Size(375, 667));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await tester.pumpWidget(
        MaterialApp(
          theme: SettloTheme.dark(),
          home: MediaQuery(
            data: MediaQueryData(textScaler: TextScaler.linear(scale)),
            child: const Scaffold(
              body: SGroup(
                children: [
                  SRow(
                    title: 'Groceries for the whole household',
                    subtitle: 'Priya paid · split three ways',
                    leading: SAvatar('Priya', size: 36),
                    trailing: Text('₹1,800'),
                    trailingSub: 'your share ₹600',
                    chevron: true,
                  ),
                  SRow(title: 'Last row', separator: false),
                ],
              ),
            ),
          ),
        ),
      );
      final row = find.byType(SRow).first;
      final avatar = find.byType(SAvatar);
      expect(tester.getSize(avatar), const Size(36, 36));
      expect(
        tester.getTopLeft(find.text('Groceries for the whole household')).dx -
            tester.getTopRight(avatar).dx,
        12,
      );
      expect(tester.getSize(row).height, greaterThanOrEqualTo(46));
      expect(tester.takeException(), isNull);
      final group = tester.widget<ClipRRect>(
        find
            .descendant(
              of: find.byType(SGroup),
              matching: find.byType(ClipRRect),
            )
            .first,
      );
      expect(group.borderRadius, BorderRadius.circular(26));
    });
  }
}
