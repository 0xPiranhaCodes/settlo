import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:settlo_core/settlo_core.dart';

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

  testWidgets('registry ignores hidden surfaces and honors Reduce Motion', (
    tester,
  ) async {
    final registry = SettloScrollRegistry();
    final hidden = ScrollController();
    final visible = ScrollController();
    addTearDown(hidden.dispose);
    addTearDown(visible.dispose);
    await tester.pumpWidget(
      MaterialApp(
        theme: SettloTheme.dark(),
        home: MediaQuery(
          data: const MediaQueryData(disableAnimations: true),
          child: SettloScrollScope(
            registry: registry,
            child: Scaffold(
              body: IndexedStack(
                index: 1,
                children: [
                  TickerMode(
                    enabled: false,
                    child: _page('Hidden', controller: hidden),
                  ),
                  TickerMode(
                    enabled: true,
                    child: _page('Visible', controller: visible),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
    hidden.jumpTo(200);
    visible.jumpTo(300);
    await tester.pump();
    expect(registry.scrollToTop(), isTrue);
    expect(visible.offset, 0);
    expect(hidden.offset, 200);
    expect(registry.scrollToTop(), isFalse);
    await tester.pumpWidget(const SizedBox());
    expect(registry.scrollToTop(), isFalse);
  });

  testWidgets('refresh invokes callback once and emits light haptic', (
    tester,
  ) async {
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
        home: Scaffold(
          body: _page(
            'Refresh',
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
    expect(feedback, contains('HapticFeedbackType.lightImpact'));
  });

  for (final platform in [TargetPlatform.iOS, TargetPlatform.android]) {
    for (final reduced in [false, true]) {
      testWidgets('native page durations $platform reduced=$reduced', (
        tester,
      ) async {
        late PageRoute<void> route;
        await tester.pumpWidget(
          MaterialApp(
            theme: SettloTheme.dark().copyWith(platform: platform),
            home: MediaQuery(
              data: MediaQueryData(disableAnimations: reduced),
              child: Navigator(
                pages: [
                  const MaterialPage<void>(child: Text('Root')),
                  SettloPage<void>(
                    child: Builder(
                      builder: (context) {
                        route = ModalRoute.of(context)! as PageRoute<void>;
                        return const Scaffold(body: Text('Detail'));
                      },
                    ),
                  ),
                ],
                onDidRemovePage: (_) {},
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        expect(
          route,
          platform == TargetPlatform.iOS
              ? isA<CupertinoPageRoute<void>>()
              : isA<MaterialPageRoute<void>>(),
        );
        expect(
          route.transitionDuration,
          reduced ? Duration.zero : isNot(Duration.zero),
        );
        expect(
          route.reverseTransitionDuration,
          reduced ? Duration.zero : isNot(Duration.zero),
        );
      });
    }
  }

  for (final scale in [1.0, 2.0]) {
    testWidgets('related form content reflows without losing names at $scale', (
      tester,
    ) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: SettloTheme.dark(),
          home: MediaQuery(
            data: MediaQueryData(textScaler: TextScaler.linear(scale)),
            child: const Scaffold(
              body: SFormBody(
                children: [
                  SResponsiveRow(
                    children: [
                      Expanded(child: Text('Rahul')),
                      SizedBox(width: 16),
                      Text('Paid 9000'),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      );
      final name = tester.getRect(find.text('Rahul'));
      final amount = tester.getRect(find.text('Paid 9000'));
      expect(name.width, greaterThan(0));
      if (scale == 2) {
        expect(amount.top, greaterThan(name.bottom));
      } else {
        expect(amount.top, name.top);
      }
    });
  }

  testWidgets(
    'shared modal has one grabber, border, and native drag dismissal',
    (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: SettloTheme.dark(),
          home: Scaffold(
            body: Builder(
              builder: (context) => TextButton(
                onPressed: () => showSettloSheet<void>(
                  context: context,
                  builder: (_) =>
                      const SizedBox(height: 240, child: Text('Panel content')),
                ),
                child: const Text('Open'),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();
      final decorations = tester
          .widgetList<Container>(find.byType(Container))
          .map((w) => w.decoration)
          .whereType<BoxDecoration>();
      expect(
        decorations.any(
          (d) => d.border != null && (d.boxShadow?.length ?? 0) == 2,
        ),
        isTrue,
      );
      expect(find.byType(BottomSheet), findsOneWidget);
      await tester.fling(
        find.text('Panel content'),
        const Offset(0, 500),
        1500,
      );
      await tester.pumpAndSettle();
      expect(find.text('Panel content'), findsNothing);
    },
  );

  testWidgets(
    'high-contrast chrome keeps actions reachable across scope changes',
    (tester) async {
      final controller = ScrollController();
      addTearDown(controller.dispose);
      var taps = 0;
      Future<void> show(
        TargetPlatform platform,
        SettloScrollRegistry registry,
      ) => tester.pumpWidget(
        MaterialApp(
          theme: SettloTheme.dark().copyWith(platform: platform),
          home: MediaQuery(
            data: const MediaQueryData(highContrast: true),
            child: SettloScrollScope(
              registry: registry,
              child: Scaffold(
                body: SettloScrollScaffold(
                  title: 'Actions',
                  controller: controller,
                  children: [
                    SettloNavigationHeader(
                      title: 'Actions',
                      leading: IconButton(
                        tooltip: 'Back',
                        onPressed: () {
                          taps++;
                        },
                        icon: const Icon(Icons.arrow_back),
                      ),
                      trailing: IconButton(
                        tooltip: 'Add',
                        onPressed: () {
                          taps++;
                        },
                        icon: const Icon(Icons.add),
                      ),
                    ),
                    const SizedBox(height: 1800),
                  ],
                ),
              ),
            ),
          ),
        ),
      );
      final oldRegistry = SettloScrollRegistry();
      await show(TargetPlatform.android, oldRegistry);
      controller.jumpTo(100);
      await tester.pump();
      final glass = tester.widget<DecoratedBox>(
        find.byKey(const ValueKey('scroll-navigation-glass')),
      );
      expect(
        (glass.decoration as BoxDecoration).color,
        SettloColors.dark.surface,
      );
      expect(
        tester.widget<BackdropFilter>(find.byType(BackdropFilter)).enabled,
        isFalse,
      );
      await tester.tap(find.byTooltip('Back'));
      await tester.tap(find.byTooltip('Add'));
      expect(taps, 2);
      final nextRegistry = SettloScrollRegistry();
      await show(TargetPlatform.iOS, nextRegistry);
      expect(oldRegistry.scrollToTop(), isFalse);
      expect(nextRegistry.scrollToTop(), isTrue);
      await tester.pumpAndSettle();
      expect(controller.offset, 0);
      expect(
        const SettloScrollBehavior().getKeyboardDismissBehavior(
          tester.element(find.byType(CustomScrollView)),
        ),
        ScrollViewKeyboardDismissBehavior.onDrag,
      );
    },
  );

  testWidgets('short slow sheet drag settles back without dismissing', (
    tester,
  ) async {
    var closed = 0;
    await tester.pumpWidget(
      MaterialApp(
        theme: SettloTheme.dark(),
        home: Scaffold(
          body: SAmountSheet(
            title: 'Amount',
            amount: const Text('2500'),
            onClose: () {
              closed++;
            },
          ),
        ),
      ),
    );
    final gesture = await tester.startGesture(const Offset(180, 12));
    await gesture.moveBy(const Offset(0, 30));
    await gesture.moveBy(const Offset(0, 30));
    await tester.pump(const Duration(milliseconds: 500));
    await gesture.up();
    await tester.pumpAndSettle();
    expect(closed, 0);
    expect(
      tester
          .widget<AnimatedContainer>(find.byType(AnimatedContainer).first)
          .transform!
          .getTranslation()
          .y,
      0,
    );
  });
}
