import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:settlo_core/theme/colors.dart';
import 'package:settlo_core/theme/tokens.dart';
import 'package:settlo_core/widgets/pressable.dart';

/// One destination in an [SGlassTabBar].
typedef SGlassTab = ({Widget icon, String label});

/// Conservative raster budget for automatic Android glass fallback.
/// Twelve slow frames in a thirty-frame window disable blur for this bar's
/// lifetime, avoiding repeated material changes during scrolling.
class GlassFrameBudget {
  int _frames = 0;
  int _slow = 0;

  /// Once exceeded, the bar stays solid until it is recreated.
  bool exceeded = false;

  /// Records a raster duration; isolated shader warmup cannot trigger fallback.
  void record(Duration raster) {
    if (exceeded) return;
    _frames++;
    if (raster > const Duration(milliseconds: 20)) _slow++;
    if (_slow >= 12) exceeded = true;
    if (_frames == 30) {
      _frames = 0;
      _slow = 0;
    }
  }
}

/// A translucent capsule over scrolling content, with a sliding bronze pill.
/// High contrast, [lowEndBlur], or sustained slow Android raster frames use an
/// opaque surface. Routes, accessible tabs and touch handling remain Flutter's.
class SGlassTabBar extends StatefulWidget {
  /// A bar over [tabs] with [currentIndex] selected.
  const new({
    required this.tabs,
    required this.currentIndex,
    required this.onTap,
    this.lowEndBlur = false,
    super.key,
  });

  /// Extra room for untruncated navigation labels at accessibility text sizes.
  static double heightFor(TextScaler scaler) => SettloElevation.tabBarHeight;

  /// The destinations, in order.
  final List<SGlassTab> tabs;

  /// Index of the selected tab.
  final int currentIndex;

  /// Called with the tapped tab's index.
  final ValueChanged<int> onTap;

  /// Explicit solid fallback for devices known to have costly blur.
  final bool lowEndBlur;

  @override
  State<SGlassTabBar> createState() => _SGlassTabBarState();
}

class _SGlassTabBarState extends State<SGlassTabBar> {
  final _budget = GlassFrameBudget();
  bool _watching = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final watch = Theme.of(context).platform == TargetPlatform.android;
    if (watch == _watching) return;
    _watching = watch;
    if (watch) {
      SchedulerBinding.instance.addTimingsCallback(_timings);
    } else {
      SchedulerBinding.instance.removeTimingsCallback(_timings);
    }
  }

  void _timings(List<FrameTiming> frames) {
    if (!mounted || _budget.exceeded) return;
    for (final frame in frames) {
      _budget.record(frame.rasterDuration);
    }
    if (_budget.exceeded) setState(() {});
  }

  @override
  void dispose() {
    if (_watching) SchedulerBinding.instance.removeTimingsCallback(_timings);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = SettloColors.of(context);
    final dark = Theme.of(context).brightness == Brightness.dark;
    final solid =
        widget.lowEndBlur ||
        MediaQuery.highContrastOf(context) ||
        _budget.exceeded;
    final reduceMotion = MediaQuery.disableAnimationsOf(context);
    final height = SGlassTabBar.heightFor(MediaQuery.textScalerOf(context));
    final radius = BorderRadius.circular(height / 2);
    final bar = Container(
      height: height,
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        // The capsule stays translucent; each glyph has a local contrast plate.
        color: solid
            ? c.surface
            : c.glass.withValues(alpha: SettloElevation.glassTint),
        borderRadius: radius,
      ),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final width = constraints.maxWidth / widget.tabs.length;
          return Stack(
            children: [
              AnimatedPositionedDirectional(
                key: const ValueKey('nav-active-pill'),
                duration: reduceMotion ? Duration.zero : SettloMotion.selection,
                curve: SettloMotion.curve,
                start: widget.currentIndex * width,
                top: 0,
                bottom: 0,
                width: width,
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular((height - 16) / 2),
                    gradient: LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: [c.navActiveStart, c.navActiveEnd],
                    ),
                  ),
                ),
              ),
              Row(
                children: [
                  for (final (i, tab) in widget.tabs.indexed)
                    Expanded(
                      child: _Tab(
                        tab: tab,
                        height: height - 16,
                        selected: i == widget.currentIndex,
                        onTap: () => widget.onTap(i),
                      ),
                    ),
                ],
              ),
            ],
          );
        },
      ),
    );
    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: radius,
        boxShadow: dark
            ? SettloElevation.floatingDark
            : SettloElevation.floatingLight,
      ),
      child: ClipRRect(
        borderRadius: radius,
        child: CustomPaint(
          foregroundPainter: _GlassEdge(c),
          child: solid
              ? bar
              : BackdropFilter(filter: SettloElevation.glassFilter, child: bar),
        ),
      ),
    );
  }
}

class _GlassEdge extends CustomPainter {
  const new(this.colors);
  final SettloColors colors;

  @override
  void paint(Canvas canvas, Size size) {
    final rect = (Offset.zero & size).deflate(0.5);
    final shape = RRect.fromRectAndRadius(
      rect,
      Radius.circular(size.height / 2),
    );
    canvas
      ..drawRRect(
        shape,
        Paint()
          ..shader = LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              colors.specular,
              colors.glassBorder.withValues(alpha: 0.03),
            ],
          ).createShader(rect)
          ..style = PaintingStyle.stroke
          ..strokeWidth = SettloElevation.hairline,
      )
      ..drawRRect(
        shape.deflate(1),
        Paint()
          ..shader = LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              colors.specular.withValues(alpha: 0.02),
              colors.specular.withValues(alpha: 0),
            ],
          ).createShader(rect),
      );
  }

  @override
  bool shouldRepaint(_GlassEdge old) => old.colors != colors;
}

class _Tab extends StatelessWidget {
  const new({
    required this.tab,
    required this.height,
    required this.selected,
    required this.onTap,
  });
  final double height;
  final SGlassTab tab;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = SettloColors.of(context);
    final color = selected ? c.onNavActive : c.textPrimary;
    final iconOnly = MediaQuery.textScalerOf(context).scale(1) >= 1.3;
    return Tooltip(
      message: tab.label,
      excludeFromSemantics: true,
      child: SPressable(
        onTap: onTap,
        selected: selected,
        label: tab.label,
        ringRadius: BorderRadius.circular(height / 2),
        child: SizedBox(
          height: height,
          child: Center(
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: selected
                    ? null
                    : c.surface.withValues(
                        alpha: SettloElevation.glassLegibility,
                      ),
                borderRadius: BorderRadius.circular(SettloRadius.compact),
              ),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    IconTheme.merge(
                      data: IconThemeData(
                        color: color,
                        size: iconOnly ? 28 : 22,
                      ),
                      child: tab.icon,
                    ),
                    if (!iconOnly) ...[
                      const SizedBox(height: 3),
                      Text(
                        tab.label,
                        maxLines: 1,
                        textAlign: TextAlign.center,
                        style: Theme.of(context).textTheme.labelSmall
                            ?.copyWith(color: color, height: 1.1),
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
