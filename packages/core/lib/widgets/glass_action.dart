import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:settlo_core/theme/colors.dart';
import 'package:settlo_core/theme/tokens.dart';

/// The running iOS's major version, 0 on other platforms. Tests set it to
/// take the iOS 26 path on the host.
int iosMajorVersion = Platform.isIOS
    ? int.tryParse(
            RegExp(r'\d+').stringMatch(Platform.operatingSystemVersion) ?? '',
          ) ??
          0
    : 0;

/// Whether the header draws iOS 26's Liquid Glass (#191): native glass
/// actions and a soft scroll edge. Earlier iOS and Android keep their look.
bool liquidGlass(BuildContext context) =>
    Theme.of(context).platform == TargetPlatform.iOS && iosMajorVersion >= 26;

/// The `UiKitView` type `GlassButton.swift` registers.
const glassActionViewType = 'app.settlo/glass_button';

/// The per-view channel, `app.settlo/glass_button/<view id>`.
String glassActionChannel(int id) => '$glassActionViewType/$id';

/// A header action: on iOS 26 and later UIKit's own glass button
/// (`UIButton.Configuration.glass()`), so it samples the content behind it;
/// [fallback] everywhere else.
class GlassAction extends StatefulWidget {
  /// A 44pt action labelled [label] that shows [symbol] or [title].
  const new({
    required this.label,
    required this.onPressed,
    required this.fallback,
    this.symbol,
    this.title,
    this.badge,
    this.asset,
    this.decorative = false,
    super.key,
  });

  /// What VoiceOver reads, the count included.
  final String label;

  /// Called on tap; null disables the button.
  final VoidCallback? onPressed;

  /// Today's Flutter button, for earlier iOS and Android.
  final Widget fallback;

  /// The SF Symbol drawn, such as `bell`.
  final String? symbol;

  /// Text drawn instead of a symbol, such as an initial.
  final String? title;

  /// A count drawn natively on the top-right edge; null draws none.
  final String? badge;

  /// A `settlo_core` image drawn as supplied instead of a symbol; its 3x file
  /// is loaded natively.
  final String? asset;

  /// Not a button: a non-interactive header element, such as Home's mark.
  final bool decorative;

  @override
  State<GlassAction> createState() => _GlassActionState();
}

class _GlassActionState extends State<GlassAction> {
  MethodChannel? _channel;
  Map<String, Object?>? _sent;

  Map<String, Object?> _state(BuildContext context) {
    final c = SettloColors.of(context);
    return {
      'label': widget.label,
      'symbol': widget.symbol,
      'title': widget.title,
      'badge': widget.badge,
      'asset': widget.asset,
      'decorative': widget.decorative,
      'enabled': widget.onPressed != null,
      'dark': Theme.of(context).brightness == Brightness.dark,
      'foreground': c.textPrimary.toARGB32(),
      // Inverted like a selected chip, never gold, as in SBell.
      'badgeColor': c.textPrimary.toARGB32(),
      'badgeText': c.background.toARGB32(),
    };
  }

  void _created(int id) {
    _channel = MethodChannel(glassActionChannel(id))
      ..setMethodCallHandler((call) async {
        if (call.method == 'tap') widget.onPressed?.call();
      });
    // Catches up on any change made before the view existed.
    unawaited(_channel?.invokeMethod<void>('update', _sent));
  }

  @override
  void dispose() {
    _channel?.setMethodCallHandler(null);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!liquidGlass(context)) return widget.fallback;
    final state = _state(context);
    if (_sent != null && !mapEquals(_sent, state)) {
      unawaited(_channel?.invokeMethod<void>('update', state));
    }
    _sent = state;
    final view = SizedBox.square(
      dimension: SettloSpacing.minTouchTarget,
      child: UiKitView(
        viewType: glassActionViewType,
        creationParams: state,
        creationParamsCodec: const StandardMessageCodec(),
        onPlatformViewCreated: _created,
        // UIKit gets the touch only once Flutter's arena gives it the tap,
        // so a drag that starts on the button still scrolls the page.
        gestureRecognizers: const {
          Factory<OneSequenceGestureRecognizer>(TapGestureRecognizer.new),
        },
      ),
    );
    // Always under an Opacity, so a fade never rebuilds the native view.
    final faded = Opacity(opacity: GlassActionFade.of(context), child: view);
    // UIKit never gets a touch, so a drag on it scrolls the page.
    return widget.decorative ? IgnorePointer(child: faded) : faded;
  }
}

/// How opaque the native [GlassAction]s below are: Flutter's blur can't
/// reach a platform view, so a header fades them out before they reach it.
class GlassActionFade extends InheritedWidget {
  /// Draws the glass actions in [child] at [opacity].
  const new({required this.opacity, required super.child, super.key});

  /// From 0, hidden, to 1.
  final double opacity;

  /// The nearest fade's opacity; 1 without one.
  static double of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<GlassActionFade>()?.opacity ??
      1;

  @override
  bool updateShouldNotify(GlassActionFade oldWidget) =>
      opacity != oldWidget.opacity;
}
