import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:settlo/native_tab_bar.dart';
import 'package:settlo/shell.dart';
import 'package:settlo_core/settlo_core.dart';

const _codec = StandardMethodCodec();
const _lastRow = Key('last-row');
final int _lightTint = SettloColors.light.action.toARGB32();

/// Stands in for `NativeTabBar.swift`: records what Flutter sends and lets a
/// test tap a tab or report a height as UIKit would.
class _FakeNativeBar {
  new(this.tester) {
    _messenger.setMockMethodCallHandler(SystemChannels.platform_views, (
      call,
    ) async {
      gestures.add(call.method);
      if (call.method == 'create') {
        final args = call.arguments as Map<Object?, Object?>;
        expect(args['viewType'], nativeTabBarViewType);
        id = args['id']! as int;
        created = const StandardMessageCodec().decodeMessage(
          ByteData.sublistView(args['params']! as Uint8List),
        ) as Map<Object?, Object?>;
        _messenger.setMockMethodCallHandler(
          MethodChannel(nativeTabBarChannel(id)),
          (call) async => updates.add(call.arguments as Map<Object?, Object?>),
        );
      }
      return null;
    });
  }

  final WidgetTester tester;
  late int id;
  late Map<Object?, Object?> created;
  final updates = <Map<Object?, Object?>>[];

  /// Platform view calls, including whether UIKit got a touch
  /// (`acceptGesture`) or had it cancelled (`rejectGesture`).
  final gestures = <String>[];

  TestDefaultBinaryMessenger get _messenger =>
      tester.binding.defaultBinaryMessenger;

  Future<void> send(String method, Object arguments, {bool pump = true}) async {
    await _messenger.handlePlatformMessage(
      nativeTabBarChannel(id),
      _codec.encodeMethodCall(MethodCall(method, arguments)),
      (_) {},
    );
    if (pump) await tester.pumpAndSettle();
  }
}

/// A shell that, like the router, selects whatever tab it is told to.
class _Host extends StatefulWidget {
  const new({required this.child, this.theme, this.taps, this.refuse = false});
  final Widget child;
  final ThemeData? theme;
  final List<int>? taps;

  /// Keeps the current tab, as a router guard would.
  final bool refuse;

  @override
  State<_Host> createState() => _HostState();
}

class _HostState extends State<_Host> {
  int index = 0;

  /// Selects [i] as a back gesture or deep link would.
  void go(int i) => setState(() => index = i);

  @override
  Widget build(BuildContext context) => MaterialApp(
    theme: (widget.theme ?? SettloTheme.light()).copyWith(
      platform: TargetPlatform.iOS,
    ),
    home: SettloShell(
      currentIndex: index,
      onTabSelected: (i) {
        widget.taps?.add(i);
        if (!widget.refuse) setState(() => index = i);
      },
      child: widget.child,
    ),
  );
}

void main() {
  testWidgets('iOS shows the system tab bar, not the Flutter glass bar', (
    tester,
  ) async {
    final native = _FakeNativeBar(tester);
    await tester.pumpWidget(const _Host(child: SizedBox()));
    await tester.pumpAndSettle();

    expect(find.byType(UiKitView), findsOneWidget);
    expect(find.byType(SGlassTabBar), findsNothing);
    expect(find.byKey(const ValueKey('nav-legibility-band')), findsNothing);
    expect(native.created, {
      'items': [
        {'label': 'Home', 'symbol': 'house'},
        {'label': 'Spaces', 'symbol': 'person.2'},
        {'label': 'Loans', 'symbol': 'banknote'},
        {'label': 'Activity', 'symbol': 'waveform.path.ecg'},
      ],
      'selected': 0,
      'dark': false,
      'tint': SettloColors.light.action.toARGB32(),
    });
  });

  testWidgets('a native tap goes to the router, which confirms it', (
    tester,
  ) async {
    final native = _FakeNativeBar(tester);
    final taps = <int>[];
    await tester.pumpWidget(_Host(taps: taps, child: const SizedBox()));
    await tester.pumpAndSettle();

    await native.send('tap', 2);

    expect(taps, [2]);
    expect(native.updates.last, {
      'selected': 2,
      'dark': false,
      'tint': _lightTint,
    });
  });

  testWidgets('a router change (back, deep link) moves the native bar', (
    tester,
  ) async {
    final native = _FakeNativeBar(tester);
    await tester.pumpWidget(const _Host(child: SizedBox()));
    await tester.pumpAndSettle();

    tester.state<_HostState>(find.byType(_Host)).go(3);
    await tester.pumpAndSettle();

    expect(native.updates.last, {
      'selected': 3,
      'dark': false,
      'tint': _lightTint,
    });
  });

  testWidgets('the app theme, not the system, sets the bar appearance', (
    tester,
  ) async {
    final native = _FakeNativeBar(tester);
    await tester.pumpWidget(
      _Host(theme: SettloTheme.dark(), child: const SizedBox()),
    );
    await tester.pumpAndSettle();

    expect(native.created['dark'], isTrue);
    expect(native.created['tint'], SettloColors.dark.action.toARGB32());
  });

  testWidgets('a refused tap snaps the native bar back without a rebuild', (
    tester,
  ) async {
    final native = _FakeNativeBar(tester);
    final taps = <int>[];
    await tester.pumpWidget(
      _Host(taps: taps, refuse: true, child: const SizedBox()),
    );
    await tester.pumpAndSettle();
    native.updates.clear();

    // UIKit has already selected 2; nothing in Flutter rebuilds.
    await native.send('tap', 2, pump: false);
    expect(taps, [2]);
    expect(tester.binding.hasScheduledFrame, isTrue);

    await tester.pump();
    expect(native.updates.last, {
      'selected': 0,
      'dark': false,
      'tint': _lightTint,
    });
  });

  testWidgets('drags outside a tab reach the back swipe and the scroll', (
    tester,
  ) async {
    final native = _FakeNativeBar(tester);
    var swiped = 0.0;
    final scroll = ScrollController();
    addTearDown(scroll.dispose);
    await tester.pumpWidget(
      GestureDetector(
        onHorizontalDragUpdate: (d) => swiped += d.delta.dx,
        child: _Host(
          child: ListView(
            controller: scroll,
            children: [
              for (var i = 0; i < 40; i++)
                SizedBox(height: 64, child: Text('Row $i')),
            ],
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    final bar = tester.getRect(find.byType(UiKitView));

    await tester.dragFrom(
      bar.topLeft + const Offset(2, 20),
      const Offset(200, 0),
    );
    await tester.pumpAndSettle();
    expect(swiped, greaterThan(0));

    await tester.dragFrom(bar.center, const Offset(0, -200));
    await tester.pumpAndSettle();
    expect(scroll.offset, greaterThan(0));
    expect(native.gestures, isNot(contains('acceptGesture')));

    // A tap on a tab is still UIKit's.
    await tester.tapAt(bar.center);
    await tester.pumpAndSettle();
    expect(native.gestures.last, 'acceptGesture');
  });

  for (final (size, bottom) in [
    (const Size(375, 667), 0.0),
    (const Size(390, 844), 34.0),
  ]) {
    testWidgets('the last row clears the reported bar on $size', (
      tester,
    ) async {
      tester.view
        ..physicalSize = size
        ..devicePixelRatio = 1
        ..viewPadding = FakeViewPadding(bottom: bottom)
        ..padding = FakeViewPadding(bottom: bottom);
      addTearDown(tester.view.reset);
      final native = _FakeNativeBar(tester);
      await tester.pumpWidget(
        _Host(
          child: Scaffold(
            body: ListView(
              children: [
                for (var i = 0; i < 40; i++)
                  SizedBox(
                    key: i == 39 ? _lastRow : null,
                    height: 64,
                    child: Text('Row $i'),
                  ),
              ],
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      // Before UIKit reports, the classic 49pt bar plus home indicator.
      expect(tester.getSize(find.byType(UiKitView)).height, 49 + bottom);

      await native.send('height', 96.0);
      await tester.drag(find.byType(ListView), const Offset(0, -5000));
      await tester.pumpAndSettle();

      final bar = tester.getRect(find.byType(UiKitView));
      expect(bar.height, 96);
      expect(bar.bottom, size.height);
      expect(
        tester.getRect(find.byKey(_lastRow)).bottom,
        lessThanOrEqualTo(bar.top),
      );
    });
  }
}
