import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

/// One destination in a [NativeTabBar]: its label and SF Symbol name.
typedef NativeTab = ({String label, String symbol});

/// The `UiKitView` type `NativeTabBar.swift` registers.
const nativeTabBarViewType = 'app.settlo/tab_bar';

/// The per-view channel, `app.settlo/tab_bar/<view id>`.
String nativeTabBarChannel(int id) => '$nativeTabBarViewType/$id';

/// The bar's height before the native side reports its own: UIKit's classic
/// 49pt plus the home indicator.
double nativeTabBarFallbackHeight(MediaQueryData media) =>
    49 + media.viewPadding.bottom;

/// The shell's tabs as Apple's own UITabBar (#157), so iOS 26 and later draw
/// system Liquid Glass and earlier iOS the standard bar. Nothing is painted
/// over it. The router stays the source of truth: taps go to [onTap] and the
/// bar is told [currentIndex] after every change, including a refused tap.
class NativeTabBar extends StatefulWidget {
  /// A bar over [tabs] with [currentIndex] selected.
  const new({
    required this.tabs,
    required this.currentIndex,
    required this.dark,
    required this.tint,
    required this.onTap,
    required this.onHeight,
    super.key,
  });

  /// The destinations, in order.
  final List<NativeTab> tabs;

  /// Index of the selected tab.
  final int currentIndex;

  /// Whether the app's theme is dark, which may differ from the system's.
  final bool dark;

  /// The selected tab's colour: Settlo's action token, never system blue.
  final Color tint;

  /// Called with the tapped tab's index, also when it is already selected.
  final ValueChanged<int> onTap;

  /// Called with the bar's height, home indicator included, as UIKit sizes it.
  final ValueChanged<double> onHeight;

  @override
  State<NativeTabBar> createState() => _NativeTabBarState();
}

class _NativeTabBarState extends State<NativeTabBar> {
  MethodChannel? _channel;

  Map<String, Object> get _state => {
    'selected': widget.currentIndex,
    'dark': widget.dark,
    'tint': widget.tint.toARGB32(),
  };

  void _created(int id) {
    _channel = MethodChannel(nativeTabBarChannel(id))
      ..setMethodCallHandler((call) async {
        switch (call.method) {
          case 'tap':
            widget.onTap(call.arguments as int);
            // The router may keep the old tab; the native bar already moved.
            // Schedule the frame too, as a refusal rebuilds nothing.
            WidgetsBinding.instance
              ..addPostFrameCallback((_) => _sync())
              ..scheduleFrame();
          case 'height':
            widget.onHeight((call.arguments as num).toDouble());
        }
      });
    _sync();
  }

  void _sync() {
    if (mounted) unawaited(_channel?.invokeMethod<void>('update', _state));
  }

  @override
  void didUpdateWidget(NativeTabBar old) {
    super.didUpdateWidget(old);
    if (old.currentIndex != widget.currentIndex ||
        old.dark != widget.dark ||
        old.tint != widget.tint) {
      _sync();
    }
  }

  @override
  void dispose() {
    _channel?.setMethodCallHandler(null);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => UiKitView(
    viewType: nativeTabBarViewType,
    creationParams: {
      'items': [
        for (final tab in widget.tabs)
          {'label': tab.label, 'symbol': tab.symbol},
      ],
      ..._state,
    },
    creationParamsCodec: const StandardMessageCodec(),
    onPlatformViewCreated: _created,
    // UIKit gets every touch this hit test reaches (AppDelegate registers
    // the hit-test blocking policy, #174). Translucent, so the back swipe
    // and the scroll behind see the same touch.
    hitTestBehavior: PlatformViewHitTestBehavior.translucent,
    gestureRecognizers: const {
      Factory<OneSequenceGestureRecognizer>(TapGestureRecognizer.new),
    },
  );
}
