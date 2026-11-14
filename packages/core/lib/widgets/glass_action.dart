import 'dart:async';
import 'dart:io';

import 'package:flutter/cupertino.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:settlo_core/theme/colors.dart';
import 'package:settlo_core/theme/tokens.dart';
import 'package:settlo_core/theme/typography.dart';
import 'package:settlo_core/widgets/pressable.dart';

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
  }) : _back = false,
       destination = null;

  /// A back capsule using the same native bridge and fallback tokens.
  const new back({required this.onPressed, this.destination, super.key})
    : _back = true,
      label = '',
      fallback = null,
      symbol = null,
      title = null,
      badge = null,
      asset = null,
      decorative = false;

  final bool _back;

  /// Full destination for accessibility, even when the visible title truncates.
  final String? destination;

  /// What VoiceOver reads, the count included.
  final String label;

  /// Called on tap; null disables the button.
  final VoidCallback? onPressed;

  /// Today's Flutter button, for earlier iOS and Android.
  final Widget? fallback;

  /// The SF Symbol drawn, such as `bell` or the neutral sheet-close `xmark`.
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
      'label': widget._back ? _backLabel : widget.label,
      'symbol': widget._back
          ? (Directionality.of(context) == TextDirection.rtl
                ? 'chevron.right'
                : 'chevron.left')
          : widget.symbol,
      'title': widget._back ? _backTitle(context) : widget.title,
      if (widget._back) ...{
        'back': true,
        'fontSize': MediaQuery.textScalerOf(context).scale(17),
        'rtl': Directionality.of(context) == TextDirection.rtl,
      },
      'badge': widget.badge,
      'asset': widget.asset,
      'decorative': widget.decorative,
      'enabled': widget.onPressed != null,
      'dark': Theme.of(context).brightness == Brightness.dark,
      'foreground':
          (widget.decorative || widget._back || widget.symbol == 'xmark'
                  ? c.textPrimary
                  : c.action)
              .toARGB32(),
      // Inverted like a selected chip, never gold, as in SBell.
      'badgeColor': c.action.toARGB32(),
      'badgeText': c.onAction.toARGB32(),
    };
  }

  String get _backLabel => widget.destination?.isNotEmpty ?? false
      ? 'Back to ${widget.destination}'
      : 'Back';

  // Bound the capsule so the navigation title and trailing action keep room.
  // At accessibility sizes the full destination stays in the spoken label.
  String? _backTitle(BuildContext context) =>
      MediaQuery.textScalerOf(context).scale(17) > 28
      ? null
      : (widget.destination?.isEmpty ?? true)
      ? null
      : widget.destination;

  double _backWidth(BuildContext context) {
    final title = _backTitle(context);
    if (title == null || title.isEmpty) return SettloSpacing.minTouchTarget;
    final painter = TextPainter(
      text: TextSpan(text: title, style: SettloTypography.body()),
      textDirection: Directionality.of(context),
      textScaler: MediaQuery.textScalerOf(context),
      maxLines: 1,
    )..layout();
    final width = (painter.width + 56).clamp(44.0, 160.0);
    painter.dispose();
    return width;
  }

  Widget _backFallback(BuildContext context) {
    final c = SettloColors.of(context);
    final title = _backTitle(context);
    return SPressable(
      label: _backLabel,
      onTap: widget.onPressed,
      ringRadius: BorderRadius.circular(SettloRadius.pill),
      child: Container(
        width: _backWidth(context),
        height: SettloSpacing.minTouchTarget,
        padding: EdgeInsets.symmetric(horizontal: title == null ? 10 : 12),
        decoration: BoxDecoration(
          color: c.glassFallback,
          border: Border.all(color: c.hairline),
          borderRadius: BorderRadius.circular(SettloRadius.pill),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(CupertinoIcons.back, color: c.textPrimary, size: 20),
            if (title != null && title.isNotEmpty) ...[
              const SizedBox(width: SettloSpacing.half),
              Flexible(
                child: Text(
                  title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: SettloTypography.body(color: c.textPrimary),
                ),
              ),
            ],
          ],
        ),
      ),
    );
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
    if (!liquidGlass(context)) {
      return widget._back ? _backFallback(context) : widget.fallback!;
    }
    final state = _state(context);
    if (_sent != null && !mapEquals(_sent, state)) {
      unawaited(_channel?.invokeMethod<void>('update', state));
    }
    _sent = state;
    final view = SizedBox(
      width: widget._back ? _backWidth(context) : SettloSpacing.minTouchTarget,
      height: SettloSpacing.minTouchTarget,
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
    // Always under the clip, so scrolling never rebuilds the native view.
    final clipped = _InsetClip(
      inset: GlassActionInset.of(context),
      child: view,
    );
    // UIKit never gets a touch, so a drag on it scrolls the page.
    return widget.decorative ? IgnorePointer(child: clipped) : clipped;
  }
}

/// The status bar's height over the native [GlassAction]s below: Flutter's
/// blur can't reach a platform view, so each is clipped where it scrolls
/// into that band, and the part still under it stays (#197).
class GlassActionInset extends InheritedWidget {
  /// Clips the glass actions in [child] above [inset] from the screen's top.
  const new({required this.inset, required super.child, super.key});

  /// The band's height, in logical pixels from the top of the screen.
  final double inset;

  /// The nearest inset; 0, clipping only above the screen, without one.
  static double of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<GlassActionInset>()?.inset ??
      0;

  @override
  bool updateShouldNotify(GlassActionInset oldWidget) =>
      inset != oldWidget.inset;
}

/// Clips its child above [inset], measured from the screen's top when
/// painted, so the clip follows the child as it scrolls.
class _InsetClip extends SingleChildRenderObjectWidget {
  const new({required this.inset, super.child});

  final double inset;

  @override
  RenderObject createRenderObject(BuildContext context) =>
      _RenderInsetClip(inset);

  @override
  void updateRenderObject(BuildContext context, _RenderInsetClip renderObject) {
    renderObject.inset = inset;
  }
}

class _RenderInsetClip extends RenderProxyBox {
  new(this._inset);

  double _inset;
  double get inset => _inset;
  set inset(double value) {
    if (value == _inset) return;
    _inset = value;
    markNeedsPaint();
  }

  /// The local rect the last paint left visible, so tests can check it.
  @visibleForTesting
  Rect visible = Rect.zero;

  @override
  void paint(PaintingContext context, Offset offset) {
    if (child == null) return;
    // Generous sideways and below, and above the view for the badge, which
    // overhangs its top edge.
    final top = _inset - localToGlobal(Offset.zero).dy;
    visible = Rect.fromLTRB(-size.width, top, size.width * 2, size.height * 2);
    layer = context.pushClipRect(
      needsCompositing,
      offset,
      visible,
      super.paint,
      oldLayer: layer as ClipRectLayer?,
    );
  }
}
