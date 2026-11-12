import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:settlo_core/settlo_core.dart';

const _codec = StandardMethodCodec();

/// Stands in for `GlassButton.swift`: records each created view's params
/// and the updates Flutter sends it.
class _FakeGlass {
  new(this.tester) {
    _messenger.setMockMethodCallHandler(SystemChannels.platform_views, (
      call,
    ) async {
      if (call.method == 'create') {
        final args = call.arguments as Map<Object?, Object?>;
        expect(args['viewType'], glassActionViewType);
        final id = args['id']! as int;
        created[id] = const StandardMessageCodec().decodeMessage(
          ByteData.sublistView(args['params']! as Uint8List),
        ) as Map<Object?, Object?>;
        _messenger.setMockMethodCallHandler(
          MethodChannel(glassActionChannel(id)),
          (call) async => updates.add(call.arguments as Map<Object?, Object?>),
        );
      }
      return null;
    });
    addTearDown(() async {
      await tester.pumpWidget(const SizedBox());
      _messenger.setMockMethodCallHandler(SystemChannels.platform_views, null);
    });
  }

  final WidgetTester tester;
  final created = <int, Map<Object?, Object?>>{};
  final updates = <Map<Object?, Object?>>[];

  TestDefaultBinaryMessenger get _messenger =>
      tester.binding.defaultBinaryMessenger;

  Future<void> tap(int id) => _messenger.handlePlatformMessage(
    glassActionChannel(id),
    _codec.encodeMethodCall(const MethodCall('tap')),
    (_) {},
  );
}

Widget _app(TargetPlatform platform, Widget child, {ThemeData? theme}) =>
    MaterialApp(
      theme: (theme ?? SettloTheme.dark()).copyWith(platform: platform),
      home: Scaffold(body: child),
    );

/// A tab root's bell and avatar, with nothing unread.
final _tabActions = ProviderScope(
  overrides: [activityUnreadProvider.overrideWith((ref) async => 0)],
  child: SettloTabActions(onBell: () {}),
);

Widget _page({Widget? trailing, String? largeTitle, bool sticky = true}) =>
    SettloScrollScaffold(
      title: 'Home',
      largeTitle: largeTitle,
      stickyHeader: sticky,
      children: [
        SettloNavigationHeader(title: 'Home', trailing: trailing),
        for (var i = 0; i < 24; i++)
          Padding(
            padding: const EdgeInsets.only(bottom: 24),
            child: SCard(child: Text('Entry $i')),
          ),
      ],
    );

/// The part of [view] its inset clip leaves visible, in its own coordinates.
Rect _visible(WidgetTester tester, Element view) {
  late Object clip;
  view.visitAncestorElements((e) {
    if (e.widget.runtimeType.toString() != '_InsetClip') return true;
    clip = e.renderObject!;
    return false;
  });
  return (clip as dynamic).visible as Rect;
}

void main() {
  tearDown(() => iosMajorVersion = 0);

  group('before iOS 26 and on Android', () {
    for (final (platform, major) in [
      (TargetPlatform.iOS, 18),
      (TargetPlatform.android, 26),
    ]) {
      testWidgets('$platform $major keeps the Flutter bell and band', (
        tester,
      ) async {
        iosMajorVersion = major;
        await tester.pumpWidget(
          _app(platform, _page(trailing: SBell(unread: 3, onPressed: () {}))),
        );
        expect(find.byType(UiKitView), findsNothing);
        expect(find.byTooltip('Notifications, 3 new'), findsOneWidget);
        expect(find.text('3'), findsOneWidget);

        await tester.drag(find.byType(CustomScrollView), const Offset(0, -400));
        await tester.pumpAndSettle();
        expect(
          find.byKey(const ValueKey('scroll-navigation-glass')),
          findsOneWidget,
        );
        expect(
          find.byKey(const ValueKey('scroll-navigation-soft-edge')),
          findsNothing,
        );
      });
    }

    testWidgets('iOS 18 large-title bar keeps its band and hairline', (
      tester,
    ) async {
      iosMajorVersion = 18;
      await tester.pumpWidget(
        _app(TargetPlatform.iOS, _page(largeTitle: 'Flat 402')),
      );
      final bar = tester.widget<CupertinoSliverNavigationBar>(
        find.byType(CupertinoSliverNavigationBar),
      );
      expect(bar.border, isNotNull);
    });
  });

  group('iOS 26', () {
    setUp(() => iosMajorVersion = 26);

    testWidgets('the bell is a native 44pt glass button with its badge', (
      tester,
    ) async {
      final glass = _FakeGlass(tester);
      var unread = 3;
      var taps = 0;
      late StateSetter setUnread;
      await tester.pumpWidget(
        _app(
          TargetPlatform.iOS,
          Center(
            child: StatefulBuilder(
              builder: (context, setState) {
                setUnread = setState;
                return SBell(unread: unread, onPressed: () => taps++);
              },
            ),
          ),
        ),
      );
      final view = tester.widget<UiKitView>(find.byType(UiKitView));
      expect(view.viewType, glassActionViewType);
      expect(tester.getSize(find.byType(UiKitView)), const Size.square(44));
      // A drag that starts on the button still reaches the scroll view.
      expect(view.gestureRecognizers, hasLength(1));
      // Flutter draws no badge or button of its own over the view.
      expect(find.byType(IconButton), findsNothing);
      expect(find.text('3'), findsNothing);
      final params = glass.created.values.single;
      expect(params['label'], 'Notifications, 3 new');
      expect(params['symbol'], 'bell');
      expect(params['badge'], '3');
      expect(params['enabled'], true);

      await glass.tap(glass.created.keys.single);
      expect(taps, 1);

      setUnread(() => unread = 0);
      await tester.pump();
      expect(glass.updates.last['badge'], isNull);
      expect(glass.updates.last['label'], 'Notifications');
    });

    testWidgets('a disabled action and a theme change reach UIKit', (
      tester,
    ) async {
      final glass = _FakeGlass(tester);
      Widget action(ThemeData theme) => _app(
        TargetPlatform.iOS,
        theme: theme,
        const Center(
          child: GlassAction(
            label: 'Download statement',
            symbol: 'arrow.down.to.line',
            onPressed: null,
            fallback: SizedBox(),
          ),
        ),
      );
      await tester.pumpWidget(action(SettloTheme.dark()));
      expect(glass.created.values.single['enabled'], false);
      expect(glass.created.values.single['dark'], true);
      await tester.pumpWidget(action(SettloTheme.light()));
      await tester.pumpAndSettle();
      expect(glass.updates.last['dark'], false);
      expect(
        glass.updates.last['foreground'],
        SettloColors.light.textPrimary.toARGB32(),
      );
    });

    testWidgets('the header has a soft edge, no strip, band or plate', (
      tester,
    ) async {
      _FakeGlass(tester);
      await tester.pumpWidget(
        _app(
          TargetPlatform.iOS,
          _page(trailing: SBell(unread: 0, onPressed: () {})),
        ),
      );
      expect(
        find.byKey(const ValueKey('scroll-navigation-soft-edge')),
        findsNothing,
      );
      await tester.drag(find.byType(CustomScrollView), const Offset(0, -400));
      await tester.pumpAndSettle();
      expect(
        find.byKey(const ValueKey('scroll-navigation-soft-edge')),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey('scroll-navigation-glass')),
        findsNothing,
      );
      final header = find.byType(SliverPersistentHeader);
      // Neither the opaque status-bar strip nor the legibility plate.
      expect(
        find
            .descendant(of: header, matching: find.byType(ColoredBox))
            .evaluate()
            .where(
              (e) =>
                  (e.widget as ColoredBox).color ==
                  SettloColors.dark.background,
            ),
        isEmpty,
      );
      final plates = find
          .descendant(of: header, matching: find.byType(DecoratedBox))
          .evaluate()
          .map((e) => (e.widget as DecoratedBox).decoration)
          .whereType<BoxDecoration>()
          .where((d) => d.color != null || d.border != null);
      expect(plates, isEmpty);
      expect(find.text('Home').hitTestable(), findsOneWidget);
    });

    for (final sticky in [true, false]) {
      testWidgets('scrolling keeps the native view IDs, sticky: $sticky', (
        tester,
      ) async {
        final glass = _FakeGlass(tester);
        await tester.pumpWidget(
          _app(
            TargetPlatform.iOS,
            _page(trailing: _tabActions, sticky: sticky),
          ),
        );
        final before = glass.created.keys.toList();
        expect(before, hasLength(2));
        for (var cycle = 0; cycle < 3; cycle++) {
          await tester.drag(
            find.byType(CustomScrollView),
            const Offset(0, -400),
          );
          await tester.pumpAndSettle();
          expect(
            find.byKey(
              ValueKey(
                sticky ? 'scroll-navigation-soft-edge' : 'scroll-status-edge',
              ),
            ),
            findsOneWidget,
          );
          await tester.drag(
            find.byType(CustomScrollView),
            const Offset(0, 1200),
          );
          await tester.pumpAndSettle();
        }
        expect(glass.created.keys.toList(), before);
      });
    }

    testWidgets('a tab root keeps only the status bar edge (#197)', (
      tester,
    ) async {
      _FakeGlass(tester);
      tester.view.padding = FakeViewPadding(
        top: 59 * tester.view.devicePixelRatio,
      );
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        _app(TargetPlatform.iOS, _page(trailing: _tabActions, sticky: false)),
      );
      final edge = find.byKey(const ValueKey('scroll-status-edge'));
      expect(edge, findsNothing);
      expect(find.byType(UiKitView), findsNWidgets(2));

      await tester.drag(find.byType(CustomScrollView), const Offset(0, -400));
      await tester.pumpAndSettle();
      // From the top of the screen to 10pt below the island line.
      final rect = tester.getRect(edge);
      expect(rect.top, 0);
      expect(rect.bottom, 59 + 10);
      expect(find.byType(BackdropFilter), findsOneWidget);
      // The title and native actions scrolled away, clipped out.
      expect(find.text('Home').hitTestable(), findsNothing);
      for (final view in find.byType(UiKitView).evaluate()) {
        expect(_visible(tester, view).top, greaterThanOrEqualTo(44));
      }
    });

    testWidgets('native actions scroll with the title, clipped at the inset', (
      tester,
    ) async {
      _FakeGlass(tester);
      tester.view.padding = FakeViewPadding(
        top: 59 * tester.view.devicePixelRatio,
      );
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        _app(TargetPlatform.iOS, _page(trailing: _tabActions, sticky: false)),
      );
      final title = tester.getTopLeft(find.text('Home')).dy;
      final views = find.byType(UiKitView);
      final rest = [
        for (final v in views.evaluate())
          tester.getTopLeft(find.byWidget(v.widget)).dy,
      ];
      final position = tester
          .state<ScrollableState>(find.byType(Scrollable).first)
          .position;
      for (final offset in [0.0, 4.0, 20.0, 40.0, 60.0]) {
        position.jumpTo(offset);
        await tester.pump();
        final moved = title - tester.getTopLeft(find.text('Home')).dy;
        expect(moved, offset, reason: 'the title follows the scroll');
        var i = 0;
        for (final view in views.evaluate()) {
          final top = tester.getTopLeft(find.byWidget(view.widget)).dy;
          expect(rest[i++] - top, moved, reason: 'in lockstep at $offset');
          // Clipped exactly at the island line, the badge's overhang above
          // the view included; everything below it still shows.
          expect(top + _visible(tester, view).top, 59);
        }
      }
    });

    testWidgets('a large-title screen fades under its bar too', (tester) async {
      await tester.pumpWidget(
        _app(TargetPlatform.iOS, _page(largeTitle: 'Flat 402')),
      );
      final edge = find.byKey(const ValueKey('scroll-navigation-soft-edge'));
      expect(edge, findsNothing);
      await tester.drag(find.byType(CustomScrollView), const Offset(0, -400));
      await tester.pumpAndSettle();
      expect(edge, findsOneWidget);
      // From the top of the screen to 32pt below the 44pt collapsed bar.
      final fade = tester.getRect(edge);
      expect(fade.top, 0);
      expect(fade.bottom, 44 + 32);
      expect(find.text('Flat 402').hitTestable(), findsWidgets);
    });

    testWidgets('a decorative mark is glass that never takes a touch', (
      tester,
    ) async {
      final glass = _FakeGlass(tester);
      await tester.pumpWidget(
        _app(
          TargetPlatform.iOS,
          Center(
            child: GlassAction(
              label: 'Settlo',
              asset: settloMarkAsset(Brightness.dark),
              decorative: true,
              onPressed: null,
              fallback: const SettloMark(),
            ),
          ),
        ),
      );
      final params = glass.created.values.single;
      expect(params['asset'], 'assets/brand/settlo_mark_dark.png');
      expect(params['decorative'], true);
      expect(params['label'], 'Settlo');
      expect(find.byType(SettloMark), findsNothing);
      expect(find.byType(UiKitView).hitTestable(), findsNothing);
    });

    testWidgets('the large-title bar has no hairline', (tester) async {
      await tester.pumpWidget(
        _app(TargetPlatform.iOS, _page(largeTitle: 'Flat 402')),
      );
      final bar = tester.widget<CupertinoSliverNavigationBar>(
        find.byType(CupertinoSliverNavigationBar),
      );
      expect(bar.border, isNull);
    });
  });
}
