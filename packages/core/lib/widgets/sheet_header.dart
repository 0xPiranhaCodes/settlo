import 'dart:async';
import 'dart:ui';

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:settlo_core/theme/colors.dart';
import 'package:settlo_core/theme/typography.dart';
import 'package:settlo_core/widgets/glass_action.dart';
import 'package:settlo_core/widgets/platform_page.dart';
import 'package:settlo_core/widgets/pressable.dart';
import 'package:settlo_core/widgets/settlo_mark.dart';

/// Flat sheet chrome; material appears only when content passes beneath it.
class SSheetHeader extends StatefulWidget {
  /// Shared sheet title and close action.
  const new({
    required this.title,
    required this.onClose,
    this.leading,
    this.onBack,
    this.onTitlePressed,
    this.titleActionLabel,
    this.scrolledUnder = false,
    this.compact = false,
    this.titleHeight,
    super.key,
  });

  /// Sheet title.
  final String title;

  /// Close action.
  final VoidCallback onClose;

  /// A 28pt avatar or mark; task sheets keep the supplied brand mark.
  final Widget? leading;

  /// Pops a nested step inside the same sheet.
  final VoidCallback? onBack;

  /// Optional action on the avatar and title, such as opening Members.
  final VoidCallback? onTitlePressed;

  /// Accessibility label for the title action.
  final String? titleActionLabel;

  /// Whether the scroll content currently overlaps this header.
  final bool scrolledUnder;

  /// Fits legacy collapsed amount panels; new sheets use the full header.
  final bool compact;

  /// Title height measured by the scaffold; legacy panels measure locally.
  final double? titleHeight;

  /// Standard header height; accessibility titles may grow.
  static const double extent = 64;

  /// Identical metrics for measuring and rendering a full-size sheet title.
  static TextStyle titleStyle({Color? color}) =>
      SettloTypography.title3(color: color)
          .copyWith(height: 1.2, letterSpacing: -.5);

  /// Inset retained for existing amount-sheet frames.
  static const double frameInset = 1;

  @override
  State<SSheetHeader> createState() => _SSheetHeaderState();
}

class _SSheetHeaderState extends State<SSheetHeader>
    with WidgetsBindingObserver {
  static const _accessibility = MethodChannel('app.settlo/accessibility');
  static final _headers = <_SSheetHeaderState>{};
  static bool _listening = false;
  bool _reduceTransparency = false;
  double _dragY = 0;

  static void _updateTransparency(bool reduced) {
    for (final header in _headers) {
      if (header.mounted && header._reduceTransparency != reduced) {
        header.setState(() => header._reduceTransparency = reduced);
      }
    }
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _headers.add(this);
    if (!_listening) {
      _listening = true;
      _accessibility.setMethodCallHandler((call) async {
        if (call.method == 'reduceTransparencyChanged') {
          _updateTransparency(call.arguments == true);
        }
      });
    }
    unawaited(_readAccessibility());
  }

  @override
  void didChangeAccessibilityFeatures() => unawaited(_readAccessibility());

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) unawaited(_readAccessibility());
  }

  Future<void> _readAccessibility() async {
    try {
      final reduced =
          await _accessibility.invokeMethod<bool>('reduceTransparency') ??
          false;
      if (mounted) _updateTransparency(reduced);
    } on MissingPluginException {
      // Other platforms have no iOS transparency preference.
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _headers.remove(this);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = SettloColors.of(context);
    final sheet = SettloSheetScope.maybeOf(context);
    final back =
        widget.onBack ??
        (sheet != null && Navigator.of(context).canPop()
            ? () => Navigator.of(context).maybePop()
            : null);
    final titleRow = ConstrainedBox(
      constraints: const BoxConstraints(minHeight: 44),
      child: Row(
        children: [
          if (back != null) ...[
            GlassAction.back(onPressed: back),
            const SizedBox(width: 12),
          ] else ...[
            SizedBox.square(
              dimension: 28,
              child:
                  widget.leading ??
                  const SettloMark(size: 28, semanticsLabel: null),
            ),
            const SizedBox(width: 12),
          ],
          Expanded(
            child: Semantics(
              header: true,
              child: LayoutBuilder(
                builder: (context, constraints) {
                  final style = SSheetHeader.titleStyle(color: c.textPrimary);
                  var measuredHeight = widget.titleHeight;
                  if (measuredHeight == null) {
                    final painter = TextPainter(
                      text: TextSpan(text: widget.title, style: style),
                      textDirection: Directionality.of(context),
                      textScaler: MediaQuery.textScalerOf(context),
                    )..layout(maxWidth: constraints.maxWidth);
                    measuredHeight = painter.height;
                    painter.dispose();
                  }
                  final constrained =
                      measuredHeight > constraints.maxHeight + .01;
                  // Existing amount panels impose a fixed navigation height.
                  // Keep the full title until they adopt the scaffold.
                  return constrained
                      ? FittedBox(
                          fit: BoxFit.scaleDown,
                          alignment: Alignment.centerLeft,
                          child: Text(widget.title, maxLines: 1, style: style),
                        )
                      : Text(widget.title, style: style);
                },
              ),
            ),
          ),
        ],
      ),
    );
    final row = LayoutBuilder(
      builder: (context, constraints) => ConstrainedBox(
        constraints: BoxConstraints(
          minHeight: widget.compact ? 52 : SSheetHeader.extent,
        ),
        child: Padding(
          padding: EdgeInsets.symmetric(
            horizontal: 16,
            // Legacy collapsing panels can be between their two extents.
            // Reduce padding first so the close target always keeps 44pt.
            vertical: ((constraints.maxHeight - 44) / 2).clamp(
              0,
              widget.compact ? 4 : 10,
            ),
          ),
          child: Row(
            children: [
              Expanded(
                child: widget.onTitlePressed == null
                    ? titleRow
                    : SPressable(
                        label: widget.titleActionLabel ?? widget.title,
                        onTap: widget.onTitlePressed,
                        child: titleRow,
                      ),
              ),
              const SizedBox(width: 12),
              GlassAction(
                label: 'Close',
                symbol: sheetCloseSymbol,
                onPressed: widget.onClose,
                fallback: SPressable(
                  onTap: widget.onClose,
                  label: 'Close',
                  ringRadius: BorderRadius.circular(22),
                  child: SizedBox.square(
                    dimension: 44,
                    child: Center(
                      child: CustomPaint(
                        size: const Size.square(22),
                        painter: _CrossPainter(c.textPrimary),
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
    return ClipRect(
      child: BackdropFilter(
        enabled: widget.scrolledUnder && !_reduceTransparency,
        filter: ImageFilter.blur(sigmaX: 30, sigmaY: 30),
        child: ColoredBox(
          color: widget.scrolledUnder
              ? c.background.withValues(alpha: _reduceTransparency ? 1 : .8)
              : const Color(0x00000000),
          child: Theme.of(context).platform == TargetPlatform.android
              ? GestureDetector(
                  excludeFromSemantics: true,
                  behavior: HitTestBehavior.opaque,
                  onVerticalDragStart: (_) => _dragY = 0,
                  onVerticalDragUpdate: (details) => _dragY += details.delta.dy,
                  onVerticalDragEnd: (details) {
                    if (_dragY > 100 || (details.primaryVelocity ?? 0) > 700) {
                      widget.onClose();
                    }
                    _dragY = 0;
                  },
                  onVerticalDragCancel: () => _dragY = 0,
                  child: row,
                )
              : row,
        ),
      ),
    );
  }
}

/// The canvas close icon: an X in a 24 box, stroke 1.6, round caps.
class _CrossPainter extends CustomPainter {
  const new(this.color);

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final scale = size.width / 24;
    final paint = Paint()
      ..color = color
      ..strokeWidth = 1.6 * scale
      ..strokeCap = StrokeCap.round;
    canvas
      ..drawLine(
        const Offset(6, 6) * scale,
        const Offset(18, 18) * scale,
        paint,
      )
      ..drawLine(
        const Offset(18, 6) * scale,
        const Offset(6, 18) * scale,
        paint,
      );
  }

  @override
  bool shouldRepaint(_CrossPainter old) => old.color != color;
}

/// A sheet body whose pinned header becomes material as content scrolls under.
class SSheetScaffold extends StatelessWidget {
  /// Builds the shared chrome and an inset scroll body.
  const new({
    required this.title,
    required this.onClose,
    required this.children,
    this.leading,
    this.onTitlePressed,
    this.titleActionLabel,
    this.onRefresh,
    super.key,
  });

  /// Sheet title.
  final String title;

  /// Close action.
  final VoidCallback onClose;

  /// Optional avatar replacing the brand mark.
  final Widget? leading;

  /// Optional action on the avatar and title, such as opening Members.
  final VoidCallback? onTitlePressed;

  /// Accessibility label for the title action.
  final String? titleActionLabel;

  /// Scroll content, already inset 16pt horizontally.
  final List<Widget> children;

  /// Optional pull-to-refresh action.
  final Future<void> Function()? onRefresh;
  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: SettloColors.of(context).background,
    body: SafeArea(
      bottom: false,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final painter =
              TextPainter(
                text: TextSpan(text: title, style: SSheetHeader.titleStyle()),
                textDirection: Directionality.of(context),
                textScaler: MediaQuery.textScalerOf(context),
              )..layout(
                maxWidth:
                    (constraints.maxWidth -
                            88 -
                            (SettloSheetScope.maybeOf(context) != null &&
                                    Navigator.of(context).canPop()
                                ? 56
                                : 40))
                        .clamp(1, double.infinity),
              );
          final titleHeight = painter.height;
          final height = (titleHeight + 20).clamp(
            SSheetHeader.extent,
            double.infinity,
          );
          painter.dispose();
          final ios = Theme.of(context).platform == TargetPlatform.iOS;
          final scroll = CustomScrollView(
            physics: ios
                ? const BouncingScrollPhysics(
                    parent: AlwaysScrollableScrollPhysics(),
                  )
                : const AlwaysScrollableScrollPhysics(),
            slivers: [
              SliverPersistentHeader(
                pinned: true,
                delegate: _SheetHeaderDelegate(
                  height: height,
                  titleHeight: titleHeight,
                  title: title,
                  leading: leading,
                  onClose: onClose,
                  onTitlePressed: onTitlePressed,
                  titleActionLabel: titleActionLabel,
                ),
              ),
              if (ios && onRefresh != null)
                CupertinoSliverRefreshControl(onRefresh: onRefresh),
              SliverPadding(
                padding: EdgeInsets.fromLTRB(
                  16,
                  16,
                  16,
                  16 + MediaQuery.paddingOf(context).bottom,
                ),
                sliver: SliverList.list(children: children),
              ),
            ],
          );
          return onRefresh == null || ios
              ? scroll
              : RefreshIndicator(onRefresh: onRefresh!, child: scroll);
        },
      ),
    ),
  );
}

class _SheetHeaderDelegate extends SliverPersistentHeaderDelegate {
  new({
    required this.height,
    required this.titleHeight,
    required this.title,
    required this.leading,
    required this.onClose,
    required this.onTitlePressed,
    required this.titleActionLabel,
  });
  final double height;
  final double titleHeight;
  final String title;
  final Widget? leading;

  /// Optional action on the avatar and title, such as opening Members.
  final VoidCallback? onTitlePressed;

  /// Accessibility label for the title action.
  final String? titleActionLabel;
  final VoidCallback onClose;
  @override
  double get minExtent => height;
  @override
  double get maxExtent => height;
  @override
  Widget build(
    BuildContext context,
    double shrinkOffset,
    bool overlapsContent,
  ) => SSheetHeader(
    title: title,
    titleHeight: titleHeight,
    onClose: onClose,
    leading: leading,
    scrolledUnder: overlapsContent || shrinkOffset > 0,
    onTitlePressed: onTitlePressed,
    titleActionLabel: titleActionLabel,
  );
  @override
  bool shouldRebuild(_SheetHeaderDelegate oldDelegate) =>
      height != oldDelegate.height ||
      titleHeight != oldDelegate.titleHeight ||
      title != oldDelegate.title ||
      leading != oldDelegate.leading ||
      onClose != oldDelegate.onClose ||
      onTitlePressed != oldDelegate.onTitlePressed ||
      titleActionLabel != oldDelegate.titleActionLabel;
}
