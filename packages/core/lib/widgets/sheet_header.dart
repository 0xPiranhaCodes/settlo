import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:settlo_core/theme/colors.dart';
import 'package:settlo_core/theme/typography.dart';
import 'package:settlo_core/widgets/glass_action.dart';
import 'package:settlo_core/widgets/pressable.dart';
import 'package:settlo_core/widgets/settlo_mark.dart';

/// Flat sheet chrome; material appears only when content passes beneath it.
class SSheetHeader extends StatelessWidget {
  /// The former grabber options remain accepted for existing callers.
  const new({
    required this.title,
    required this.onClose,
    this.leading,
    this.onTitlePressed,
    this.titleActionLabel,
    this.scrolledUnder = false,
    this.compact = false,
    this.showGrabber = true,
    super.key,
  });

  /// Sheet title.
  final String title;

  /// Close action.
  final VoidCallback onClose;

  /// A 28pt avatar or mark; defaults to the supplied brand mark.
  final Widget? leading;

  /// Optional action on the avatar and title, such as opening Members.
  final VoidCallback? onTitlePressed;

  /// Accessibility label for the title action.
  final String? titleActionLabel;

  /// Whether the scroll content currently overlaps this header.
  final bool scrolledUnder;

  /// Fits legacy collapsed amount panels; new sheets use the full header.
  final bool compact;

  /// Retained for source compatibility; sheet chrome has no grabber.
  final bool showGrabber;

  /// Standard header height; accessibility titles may grow.
  static const double extent = 64;

  /// Inset retained for existing amount-sheet frames.
  static const double frameInset = 1;

  @override
  Widget build(BuildContext context) {
    final c = SettloColors.of(context);
    final titleRow = ConstrainedBox(
      constraints: const BoxConstraints(minHeight: 44),
      child: Row(
        children: [
          SizedBox.square(
            dimension: 28,
            child: leading ?? const SettloMark(size: 28, semanticsLabel: null),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Semantics(
              header: true,
              child: LayoutBuilder(
                builder: (context, constraints) {
                  final style = SettloTypography.title3(color: c.textPrimary)
                      .copyWith(height: 1.2);
                  final painter = TextPainter(
                    text: TextSpan(text: title, style: style),
                    textDirection: Directionality.of(context),
                    textScaler: MediaQuery.textScalerOf(context),
                  )..layout(maxWidth: constraints.maxWidth);
                  final constrained =
                      painter.height > constraints.maxHeight + .01;
                  painter.dispose();
                  // Existing amount panels impose a fixed navigation height.
                  // Keep the full title until they adopt the scaffold.
                  return constrained
                      ? FittedBox(
                          fit: BoxFit.scaleDown,
                          alignment: Alignment.centerLeft,
                          child: Text(title, maxLines: 1, style: style),
                        )
                      : Text(title, style: style);
                },
              ),
            ),
          ),
        ],
      ),
    );
    final row = LayoutBuilder(
      builder: (context, constraints) => ConstrainedBox(
        constraints: BoxConstraints(minHeight: compact ? 52 : extent),
        child: Padding(
          padding: EdgeInsets.symmetric(
            horizontal: 16,
            // Legacy collapsing panels can be between their two extents.
            // Reduce padding first so the close target always keeps 44pt.
            vertical: ((constraints.maxHeight - 44) / 2).clamp(
              0,
              compact ? 4 : 10,
            ),
          ),
          child: Row(
            children: [
              Expanded(
                child: onTitlePressed == null
                    ? titleRow
                    : SPressable(
                        label: titleActionLabel ?? title,
                        onTap: onTitlePressed,
                        child: titleRow,
                      ),
              ),
              const SizedBox(width: 12),
              GlassAction(
                label: 'Close',
                symbol: 'xmark',
                onPressed: onClose,
                fallback: SPressable(
                  onTap: onClose,
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
        enabled: scrolledUnder,
        filter: ImageFilter.blur(sigmaX: 30, sigmaY: 30),
        child: ColoredBox(
          color: scrolledUnder
              ? c.background.withValues(alpha: .8)
              : const Color(0x00000000),
          child: row,
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
                text: TextSpan(
                  text: title,
                  style: SettloTypography.title3().copyWith(height: 1.2),
                ),
                textDirection: Directionality.of(context),
                textScaler: MediaQuery.textScalerOf(context),
              )..layout(
                maxWidth: (constraints.maxWidth - 128).clamp(
                  1,
                  double.infinity,
                ),
              );
          final height = (painter.height + 20).clamp(
            SSheetHeader.extent,
            double.infinity,
          );
          painter.dispose();
          final scroll = CustomScrollView(
            physics: const AlwaysScrollableScrollPhysics(),
            slivers: [
              SliverPersistentHeader(
                pinned: true,
                delegate: _SheetHeaderDelegate(
                  height: height,
                  title: title,
                  leading: leading,
                  onClose: onClose,
                  onTitlePressed: onTitlePressed,
                  titleActionLabel: titleActionLabel,
                ),
              ),
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
          return onRefresh == null
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
    required this.title,
    required this.leading,
    required this.onClose,
    required this.onTitlePressed,
    required this.titleActionLabel,
  });
  final double height;
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
    onClose: onClose,
    leading: leading,
    scrolledUnder: overlapsContent || shrinkOffset > 0,
    onTitlePressed: onTitlePressed,
    titleActionLabel: titleActionLabel,
  );
  @override
  bool shouldRebuild(_SheetHeaderDelegate oldDelegate) =>
      height != oldDelegate.height ||
      title != oldDelegate.title ||
      leading != oldDelegate.leading ||
      onClose != oldDelegate.onClose ||
      onTitlePressed != oldDelegate.onTitlePressed ||
      titleActionLabel != oldDelegate.titleActionLabel;
}
