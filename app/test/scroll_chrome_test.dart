import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:settlo/shell.dart';
import 'package:settlo_core/settlo_core.dart';
import 'package:settlo_test_support/golden.dart';

Widget _page(
  String title, {
  ScrollController? controller,
  Future<void> Function()? refresh,
}) => SettloScrollScaffold(
  title: title,
  controller: controller,
  onRefresh: refresh,
  children: [
    SettloNavigationHeader(title: title),
    for (var i = 0; i < 24; i++)
      Padding(
        padding: const EdgeInsets.only(bottom: 24),
        child: SCard(
          child: Text('$title entry $i', style: SettloTypography.body()),
        ),
      ),
  ],
);

void main() {
  for (final platform in [TargetPlatform.iOS, TargetPlatform.android]) {
    testWidgets('native physics and refresh control on $platform', (
      tester,
    ) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: SettloTheme.dark().copyWith(platform: platform),
          scrollBehavior: const SettloScrollBehavior(),
          home: Scaffold(body: _page('Activity', refresh: () async {})),
        ),
      );
      final view = tester.widget<CustomScrollView>(
        find.byType(CustomScrollView),
      );
      expect(
        view.physics,
        platform == TargetPlatform.iOS
            ? isA<BouncingScrollPhysics>()
            : isA<ClampingScrollPhysics>(),
      );
      expect(
        view.keyboardDismissBehavior,
        ScrollViewKeyboardDismissBehavior.onDrag,
      );
      expect(
        find.byType(CupertinoSliverRefreshControl, skipOffstage: false),
        platform == TargetPlatform.iOS ? findsOneWidget : findsNothing,
      );
      expect(
        find.byType(RefreshIndicator),
        platform == TargetPlatform.android ? findsOneWidget : findsNothing,
      );
      if (platform == TargetPlatform.android) {
        expect(find.byType(StretchingOverscrollIndicator), findsOneWidget);
      }
    });
  }

  testWidgets('header pins, collapses and gains glass only when scrolled', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: SettloTheme.dark(),
        home: Scaffold(body: _page('Spaces')),
      ),
    );
    expect(find.byKey(const ValueKey('scroll-navigation-glass')), findsNothing);
    final before = tester
        .renderObject<RenderSliver>(find.byType(SliverPersistentHeader))
        .geometry!;
    await tester.drag(find.byType(CustomScrollView), const Offset(0, -400));
    await tester.pumpAndSettle();
    expect(
      find.byKey(const ValueKey('scroll-navigation-glass')),
      findsOneWidget,
    );
    expect(
      tester
          .renderObject<RenderSliver>(find.byType(SliverPersistentHeader))
          .geometry!
          .paintExtent,
      lessThan(before.paintExtent),
    );
    expect(find.text('Spaces').hitTestable(), findsOneWidget);
  });

  testWidgets(
    'active tab scrolls first, then returns to root; switching keeps position',
    (tester) async {
      final first = ScrollController();
      final second = ScrollController();
      addTearDown(first.dispose);
      addTearDown(second.dispose);
      var index = 0;
      var resets = 0;
      await tester.pumpWidget(
        MaterialApp(
          theme: SettloTheme.dark(),
          home: StatefulBuilder(
            builder: (context, setState) => SettloShell(
              currentIndex: index,
              onTabSelected: (next) {
                if (next == index) resets++;
                setState(() => index = next);
              },
              child: IndexedStack(
                index: index,
                children: [
                  TickerMode(
                    enabled: index == 0,
                    child: _page('SETTLO', controller: first),
                  ),
                  TickerMode(
                    enabled: index == 1,
                    child: _page('Spaces', controller: second),
                  ),
                ],
              ),
            ),
          ),
        ),
      );
      first.jumpTo(300);
      await tester.pump();
      await tester.tap(find.byTooltip('Spaces'));
      await tester.pumpAndSettle();
      second.jumpTo(150);
      await tester.pump();
      await tester.tap(find.byTooltip('Home'));
      await tester.pumpAndSettle();
      expect(first.offset, 300);
      expect(second.offset, 150);
      await tester.tap(find.byTooltip('Home'));
      await tester.pumpAndSettle();
      expect(first.offset, 0);
      expect(resets, 0);
      await tester.tap(find.byTooltip('Home'));
      await tester.pumpAndSettle();
      expect(resets, 1);
    },
  );

  testWidgets('iOS status area uses its primary controller to scroll to top', (
    tester,
  ) async {
    final controller = ScrollController();
    addTearDown(controller.dispose);
    await tester.pumpWidget(
      MaterialApp(
        theme: SettloTheme.dark().copyWith(platform: TargetPlatform.iOS),
        home: Scaffold(body: _page('Loans', controller: controller)),
      ),
    );
    controller.jumpTo(400);
    await tester.pump();
    await tester.tapAt(const Offset(160, 20));
    await tester.pumpAndSettle();
    expect(controller.offset, 0);
  });

  testWidgets('refresh and tab switching issue light haptics', (tester) async {
    final feedback = <String>[];
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      (call) async {
        if (call.method == 'HapticFeedback.vibrate') {
          feedback.add(call.arguments as String);
        }
        return null;
      },
    );
    addTearDown(
      () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        null,
      ),
    );
    var refreshed = 0;
    await tester.pumpWidget(
      MaterialApp(
        theme: SettloTheme.dark().copyWith(platform: TargetPlatform.android),
        home: SettloShell(
          currentIndex: 0,
          onTabSelected: (_) {},
          child: _page(
            'SETTLO',
            refresh: () async {
              refreshed++;
            },
          ),
        ),
      ),
    );
    await tester.drag(find.byType(CustomScrollView), const Offset(0, 500));
    await tester.pumpAndSettle();
    expect(refreshed, 1);
    await tester.tap(find.byTooltip('Spaces'));
    await tester.pumpAndSettle();
    expect(
      feedback.where((value) => value == 'HapticFeedbackType.lightImpact'),
      hasLength(2),
    );
  });

  testWidgets(
    'large-text navigation uses semantic icons and a long-press tooltip',
    (tester) async {
      final semantics = tester.ensureSemantics();

      await tester.pumpWidget(
        MaterialApp(
          theme: SettloTheme.dark(),
          home: MediaQuery(
            data: const MediaQueryData(textScaler: TextScaler.linear(1.3)),
            child: Center(
              child: SGlassTabBar(
                tabs: const [
                  (icon: Icon(Icons.home), label: 'Home'),
                  (icon: Icon(Icons.list), label: 'Activity'),
                ],
                currentIndex: 0,
                onTap: (_) {},
              ),
            ),
          ),
        ),
      );
      expect(find.text('Activity'), findsNothing);
      expect(find.bySemanticsLabel('Activity'), findsOneWidget);
      await tester.longPress(find.byTooltip('Activity'));
      await tester.pumpAndSettle();
      expect(find.text('Activity'), findsOneWidget);
      semantics.dispose();
    },
  );

  testWidgets('amount panel follows its grabber and flings to dismiss', (
    tester,
  ) async {
    var dismissed = 0;
    await tester.pumpWidget(
      MaterialApp(
        theme: SettloTheme.dark(),
        home: Scaffold(
          body: SAmountSheet(
            title: 'Record repayment',
            amount: const Text('2500'),
            onClose: () {
              dismissed++;
            },
          ),
        ),
      ),
    );
    final gesture = await tester.startGesture(const Offset(180, 12));
    await gesture.moveBy(const Offset(0, 40));
    await gesture.moveBy(const Offset(0, 40));
    await tester.pump();
    final panel = tester.widget<AnimatedContainer>(
      find.byType(AnimatedContainer).first,
    );
    expect(panel.transform!.getTranslation().y, greaterThan(0));
    await gesture.moveBy(const Offset(0, 100));
    await gesture.up();
    await tester.pumpAndSettle();
    expect(dismissed, 1);
  });

  testWidgets('native iOS page supports edge-swipe back', (tester) async {
    var detail = true;
    await tester.pumpWidget(
      MaterialApp(
        theme: SettloTheme.dark().copyWith(platform: TargetPlatform.iOS),
        home: StatefulBuilder(
          builder: (context, setState) => Navigator(
            pages: [
              const MaterialPage<void>(
                child: Scaffold(body: Center(child: Text('Root page'))),
              ),
              if (detail)
                const SettloPage<void>(
                  child: Scaffold(body: Center(child: Text('Detail page'))),
                ),
            ],
            onDidRemovePage: (_) => setState(() => detail = false),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.flingFrom(const Offset(1, 300), const Offset(600, 0), 1200);
    await tester.pumpAndSettle();
    expect(detail, isFalse);
    expect(find.text('Root page'), findsOneWidget);
  });

  for (final device in SettloGoldenDevices.accessible) {
    for (final (name, theme) in [
      ('dark', SettloTheme.dark()),
      ('light', SettloTheme.light()),
    ]) {
      for (final scrolled in [false, true]) {
        testWidgets('scroll chrome ${device.name} $name $scrolled golden', (
          tester,
        ) async {
          await pumpSettloGolden(
            tester,
            device: device,
            theme: theme,
            child: Scaffold(body: _page('Spaces')),
            act: scrolled
                ? (tester) async {
                    await tester.drag(
                      find.byType(CustomScrollView),
                      const Offset(0, -300),
                    );
                  }
                : null,
          );
          await expectLater(
            find.byKey(settloGoldenSurfaceKey),
            matchesGoldenFile(
              'goldens/scroll_${scrolled ? 'scrolled' : 'rest'}_${device.name}_$name.png',
            ),
          );
        });
      }
    }
  }
}
