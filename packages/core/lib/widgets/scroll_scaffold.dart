import 'dart:async';
import 'dart:ui' show ImageFilter;

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';
import 'package:settlo_core/theme/colors.dart';
import 'package:settlo_core/theme/tokens.dart';
import 'package:settlo_core/theme/typography.dart';
import 'package:settlo_core/widgets/glass_action.dart';
import 'package:settlo_core/widgets/glass_tab_bar.dart';

/// Native scrolling and keyboard dismissal for every application scroll view.
class SettloScrollBehavior extends MaterialScrollBehavior {
  /// Uses the current platform without overriding touch or pointer support.
  const new();

  @override
  ScrollPhysics getScrollPhysics(BuildContext context) =>
      getPlatform(context) == TargetPlatform.iOS
      ? const BouncingScrollPhysics(parent: AlwaysScrollableScrollPhysics())
      : const ClampingScrollPhysics(parent: AlwaysScrollableScrollPhysics());

  @override
  ScrollViewKeyboardDismissBehavior getKeyboardDismissBehavior(
    BuildContext context,
  ) => ScrollViewKeyboardDismissBehavior.onDrag;
}

/// Shell-owned registry of scroll surfaces. Hidden tabs keep their state.
class SettloScrollRegistry {
  final _surfaces = <_SettloScrollScaffoldState>{};

  /// Scrolls the visible route first. A later re-tap can pop its branch.
  bool scrollToTop() {
    for (final surface in _surfaces.toList().reversed) {
      if (surface.mounted &&
          TickerMode.valuesOf(surface.context).enabled &&
          (ModalRoute.of(surface.context)?.isCurrent ?? true) &&
          surface._controller.hasClients &&
          surface._controller.offset > 0) {
        surface._toTop();
        return true;
      }
    }
    return false;
  }
}

/// Makes the shell registry available without changing routes or providers.
class SettloScrollScope extends InheritedWidget {
  /// Wraps all branches in one registry.
  const new({required this.registry, required super.child, super.key});

  /// Mounted branch scroll surfaces.
  final SettloScrollRegistry registry;

  @override
  bool updateShouldNotify(SettloScrollScope oldWidget) =>
      registry != oldWidget.registry;
}

/// Shared sliver chrome. The first child is the expanded mock header; the rest
/// form a lazily laid out list below the pinned, collapsing navigation bar.
class SettloScrollScaffold extends StatefulWidget {
  /// Native scrolling with an optional refresh operation.
  const new({
    required this.title,
    required this.children,
    this.padding = const EdgeInsets.all(SettloSpacing.screenMargin),
    this.controller,
    this.onRefresh,
    this.compactHeader,
    this.slivers,
    this.statusInset,
    this.expandedHeight = 84,
    this.headerGap = 0,
    this.largeTitle,
    this.previousPageTitle,
    this.trailing,
    super.key,
  });

  /// Compact navigation title, also used as the scroll-position identity.
  final String title;

  /// Expanded header first, then page content.
  final List<Widget> children;

  /// Screen edges and bottom safe-area inset; top is supplied by the bar.
  final EdgeInsetsGeometry padding;

  /// Optional feature controller (for example Activity pagination).
  final ScrollController? controller;

  /// Pull-to-refresh operation, called once per gesture by the native control.
  final Future<void> Function()? onRefresh;

  /// A compact header retaining route-specific actions such as Home's bell.
  final Widget? compactHeader;

  /// Custom slivers for forms with a footer or fill-remaining layout.
  final List<Widget>? slivers;

  /// Panels already below the status bar pass zero.
  final double? statusInset;

  /// Height below the status bar while expanded.
  final double expandedHeight;

  /// Explicit space after the header; child spacers are never discarded.
  final double headerGap;

  /// On iOS, a detail screen's native navigation bar: this title starts large
  /// and collapses, the standard back chevron is labelled
  /// [previousPageTitle], and the expanded header (the first child, with its
  /// own back button) is left out. Other platforms keep the Settlo header.
  final String? largeTitle;

  /// The title of the screen back returns to, such as `Spaces`.
  final String? previousPageTitle;

  /// The native bar's trailing item.
  final Widget? trailing;

  @override
  State<SettloScrollScaffold> createState() => _SettloScrollScaffoldState();
}

class _SettloScrollScaffoldState extends State<SettloScrollScaffold> {
  // Inside an iOS task sheet, scroll on the sheet's controller so a drag
  // down at the top dismisses it.
  late final ScrollController? _sheet =
      CupertinoSheetRoute.hasParentSheet(context)
      ? PrimaryScrollController.maybeOf(context)
      : null;
  late final ScrollController _controller =
      widget.controller ?? _sheet ?? ScrollController();
  SettloScrollRegistry? _registry;
  final _budget = GlassFrameBudget();
  bool _watching = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final watch = Theme.of(context).platform == TargetPlatform.android;
    if (watch != _watching) {
      _watching = watch;
      if (watch) {
        SchedulerBinding.instance.addTimingsCallback(_timings);
      } else {
        SchedulerBinding.instance.removeTimingsCallback(_timings);
      }
    }
    final registry = context
        .dependOnInheritedWidgetOfExactType<SettloScrollScope>()
        ?.registry;
    if (registry != _registry) {
      _registry?._surfaces.remove(this);
      _registry = registry;
      registry?._surfaces.add(this);
    }
  }

  void _timings(List<FrameTiming> frames) {
    if (!mounted || _budget.exceeded) return;
    for (final frame in frames) {
      _budget.record(frame.rasterDuration);
    }
    if (_budget.exceeded) setState(() {});
  }

  void _toTop() {
    if (!_controller.hasClients) return;
    if (MediaQuery.disableAnimationsOf(context)) {
      _controller.jumpTo(0);
    } else {
      _controller.animateTo(
        0,
        duration: SettloMotion.selection,
        curve: SettloMotion.curve,
      );
    }
  }

  Future<void> _refresh() async {
    unawaited(HapticFeedback.lightImpact());
    await widget.onRefresh?.call();
  }

  Widget _largeTitleBar(BuildContext context, String title) {
    final c = SettloColors.of(context);
    final dark = Theme.of(context).brightness == Brightness.dark;
    final solid = MediaQuery.highContrastOf(context);
    // iOS 26 has no tinted band or hairline under the bar (#191); the soft
    // edge sliver after it draws the page colour instead.
    final glass = liquidGlass(context);
    return CupertinoTheme(
      // Settlo tokens, never system blue: the chevron and bar items are
      // primary text, and the titles stay on Figtree's HIG ramp.
      data: CupertinoThemeData(
        brightness: Theme.of(context).brightness,
        primaryColor: c.textPrimary,
        textTheme: CupertinoTextThemeData(
          primaryColor: c.textPrimary,
          navLargeTitleTextStyle: SettloTypography.largeTitle(
            color: c.textPrimary,
          ),
          navTitleTextStyle: SettloTypography.headline(color: c.textPrimary),
          navActionTextStyle: SettloTypography.body(color: c.textPrimary),
        ),
      ),
      child: CupertinoSliverNavigationBar(
        largeTitle: Text(title),
        previousPageTitle: widget.previousPageTitle,
        trailing: widget.trailing,
        // Clear keeps the page colour's luminance for the status bar style.
        backgroundColor: solid
            ? c.surface
            : glass
            ? c.background.withValues(alpha: 0)
            : c.glass.withValues(alpha: SettloElevation.glassTint),
        enableBackgroundFilterBlur: !glass,
        border: glass
            ? null
            : Border(
                bottom: BorderSide(color: SettloElevation.border(dark: dark)),
              ),
      ),
    );
  }

  @override
  void dispose() {
    if (_watching) SchedulerBinding.instance.removeTimingsCallback(_timings);
    _registry?._surfaces.remove(this);
    if (widget.controller == null && _sheet == null) _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final ios = Theme.of(context).platform == TargetPlatform.iOS;
    final padding = widget.padding.resolve(Directionality.of(context));
    // A native sheet already sits below the status bar.
    final top =
        widget.statusInset ??
        (CupertinoSheetRoute.hasParentSheet(context)
            ? 0.0
            : MediaQuery.paddingOf(context).top.clamp(44.0, double.infinity));
    final header = widget.children.isEmpty
        ? const SizedBox.shrink()
        : widget.children.first;
    final largeTitle = ios ? widget.largeTitle : null;
    // The native bar starts right under the status bar.
    final statusTap = largeTitle == null
        ? top
        : MediaQuery.paddingOf(context).top;
    final scroll = CustomScrollView(
      key: PageStorageKey('scroll-${widget.title}'),
      primary: true,
      physics: const SettloScrollBehavior().getScrollPhysics(context),
      keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
      slivers: [
        if (largeTitle != null) _largeTitleBar(context, largeTitle),
        if (largeTitle != null &&
            liquidGlass(context) &&
            !MediaQuery.highContrastOf(context))
          _SliverSoftEdge(
            child: LayoutBuilder(
              builder: (context, box) => _SoftEdge(
                // Fades in over the first 16pt of content under the bar.
                strength: ((box.maxHeight - _softEdgeFade) / 16).clamp(
                  0.0,
                  1.0,
                ),
                color: SettloColors.of(context).background,
                blur: true,
              ),
            ),
          ),
        if (largeTitle == null)
          SliverPersistentHeader(
            pinned: true,
            delegate: _NavigationHeader(
              top: top,
              forceSolid: _budget.exceeded,
              glass: liquidGlass(context),
              expandedHeight: widget.expandedHeight,
              title: widget.title,
              expanded: header,
              compact: widget.compactHeader ?? header,
            ),
          ),
        if (ios && widget.onRefresh != null)
          CupertinoSliverRefreshControl(onRefresh: _refresh),
        if (widget.slivers case final body?)
          ...body
        else
          SliverPadding(
            padding: EdgeInsets.fromLTRB(
              padding.left,
              widget.headerGap,
              padding.right,
              padding.bottom,
            ),
            sliver: SliverList.list(children: widget.children.skip(1).toList()),
          ),
      ],
    );
    return PrimaryScrollController(
      controller: _controller,
      child: Stack(
        children: [
          if (!ios && widget.onRefresh != null)
            RefreshIndicator(onRefresh: _refresh, child: scroll)
          else
            scroll,
          if (ios && statusTap > 0)
            Positioned(
              top: 0,
              left: 0,
              right: 0,
              height: statusTap,
              child: GestureDetector(
                excludeFromSemantics: true,
                behavior: HitTestBehavior.opaque,
                onTap: _toTop,
                child: const SizedBox.expand(),
              ),
            ),
        ],
      ),
    );
  }
}

class _NavigationHeader extends SliverPersistentHeaderDelegate {
  new({
    required this.top,
    required this.forceSolid,
    required this.glass,
    required this.expandedHeight,
    required this.title,
    required this.expanded,
    required this.compact,
  });
  final double top;
  final bool forceSolid;

  /// iOS 26: a soft scroll edge instead of the band, strip and plate.
  final bool glass;
  final double expandedHeight;
  final String title;
  final Widget expanded;
  final Widget compact;

  @override
  double get minExtent => top + 56;
  @override
  double get maxExtent => top + expandedHeight;

  @override
  Widget build(
    BuildContext context,
    double shrinkOffset,
    bool overlapsContent,
  ) {
    final c = SettloColors.of(context);
    final scrolled = shrinkOffset > 0 || overlapsContent;
    final collapsed = shrinkOffset >= (maxExtent - minExtent).clamp(0, 28);
    final dark = Theme.of(context).brightness == Brightness.dark;
    final solid = MediaQuery.highContrastOf(context) || forceSolid;
    final bar = ClipRect(
      child: Stack(
        fit: StackFit.expand,
        children: [
          if (scrolled && !glass)
            BackdropFilter(
              enabled: !solid,
              filter: SettloElevation.glassFilter,
              child: DecoratedBox(
                key: const ValueKey('scroll-navigation-glass'),
                decoration: BoxDecoration(
                  color: solid
                      ? c.surface
                      : c.glass.withValues(alpha: SettloElevation.glassTint),
                  border: Border(
                    bottom: BorderSide(
                      color: SettloElevation.border(dark: dark),
                    ),
                  ),
                ),
              ),
            ),
          if (!glass)
            Positioned(
              top: 0,
              left: 0,
              right: 0,
              height: top,
              child: ColoredBox(color: c.background),
            ),
          Positioned(
            left: 20,
            right: 20,
            top: top,
            bottom: (24 - shrinkOffset).clamp(0, 24),
            child: Center(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: scrolled && !glass
                      ? c.surface.withValues(
                          alpha: SettloElevation.glassLegibility,
                        )
                      : null,
                  borderRadius: BorderRadius.circular(SettloRadius.compact),
                ),
                child: SizedBox(
                  width: double.infinity,
                  child: DefaultTextStyle.merge(
                    style: SettloTypography.title2(color: c.textPrimary),
                    child: _ChromeState(
                      compact: collapsed,
                      child: collapsed ? compact : expanded,
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
    if (!glass) return bar;
    // The edge hangs below the bar, so the bar itself is fully covered and
    // the fade happens over the content under it, as on iOS 26. The tree is
    // the same at rest, so the header's native glass views are never rebuilt.
    return Stack(
      clipBehavior: Clip.none,
      fit: StackFit.expand,
      children: [
        Positioned(
          top: 0,
          left: 0,
          right: 0,
          bottom: -_softEdgeFade,
          child: _SoftEdge(
            // Fades in over the first 16pt of scroll, so it never pops.
            strength: overlapsContent ? 1 : (shrinkOffset / 16).clamp(0.0, 1.0),
            color: solid ? c.surface : c.background,
            blur: !solid,
          ),
        ),
        bar,
      ],
    );
  }

  @override
  bool shouldRebuild(_NavigationHeader oldDelegate) => true;
}

/// The page colour's opacity at the top of the iOS 26 edge and at the bar's
/// bottom. Light mode thins out towards the title row, as natively, so it
/// reads as frosted glass rather than a grey band.
(double, double) _softEdgeAlpha(Color page) =>
    page.computeLuminance() > 0.5 ? (0.94, 0.78) : (0.86, 0.86);

/// How far below the bar the iOS 26 edge fades out.
const _softEdgeFade = 24.0;

/// iOS 26's soft scroll edge (#191): the page colour and a blur, strongest
/// under the status bar and fading out downwards, with no band, plate or
/// hairline. [strength] scales the whole edge from none to full.
class _SoftEdge extends StatelessWidget {
  const new({required this.strength, required this.color, required this.blur});

  final double strength;
  final Color color;
  final bool blur;

  @override
  Widget build(BuildContext context) => strength == 0
      ? const SizedBox.expand()
      : LayoutBuilder(
          builder: (context, box) =>
              _edge((box.maxHeight - _softEdgeFade) / box.maxHeight),
        );

  /// Full down to [full] of the height, then fading out.
  Widget _edge(double full) {
    final (top, bottom) = blur ? _softEdgeAlpha(color) : (1.0, 1.0);
    return Stack(
      key: const ValueKey('scroll-navigation-soft-edge'),
      fit: StackFit.expand,
      children: [
        // A progressive blur: each layer also blurs the ones before it, so
        // the blur thins out down the fade with only small steps. No mask
        // layer: Impeller drew nothing for a ShaderMask over a BackdropFilter.
        if (blur)
          for (final (end, sigma) in [
            (1.0, 3.0),
            ((1 + full) / 2, 6.0),
            (full, 14.0),
          ])
            FractionallySizedBox(
              alignment: Alignment.topCenter,
              heightFactor: end,
              child: ClipRect(
                child: BackdropFilter(
                  filter: ImageFilter.blur(
                    sigmaX: sigma * strength,
                    sigmaY: sigma * strength,
                  ),
                  child: const SizedBox.expand(),
                ),
              ),
            ),
        // Strongest under the status bar, so the clock never sits on content.
        DecoratedBox(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [
                color.withValues(alpha: top * strength),
                color.withValues(alpha: bottom * strength),
                color.withValues(alpha: 0),
              ],
              stops: [0, full, 1],
            ),
          ),
        ),
      ],
    );
  }
}

/// Takes no scroll space after a pinned bar and paints its child from the
/// top of the content under that bar to [_softEdgeFade] below it, beneath the
/// bar's title and buttons, so large-title screens fade like Home (#191).
class _SliverSoftEdge extends SingleChildRenderObjectWidget {
  const new({required Widget super.child});

  @override
  RenderObject createRenderObject(BuildContext context) =>
      _RenderSliverSoftEdge();
}

class _RenderSliverSoftEdge extends RenderSliverSingleBoxAdapter {
  @override
  void performLayout() {
    final under = constraints.overlap;
    child!.layout(
      BoxConstraints.tightFor(
        width: constraints.crossAxisExtent,
        height: under + _softEdgeFade,
      ),
    );
    // Zero extent and hit area; painted only while content is under the bar.
    geometry = SliverGeometry(visible: under > 0);
  }
}

/// Header layout shared by tab titles and their persistent trailing actions.
class SettloNavigationHeader extends StatelessWidget {
  /// Keeps actions reachable in both the expanded and compact bar.
  const new({required this.title, this.leading, this.trailing, super.key});

  /// Accessible title.
  final String title;

  /// Optional back control.
  final Widget? leading;

  /// Optional add or notification control.
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final compact =
        context.dependOnInheritedWidgetOfExactType<_ChromeState>()?.compact ??
        false;
    final label = Semantics(
      header: true,
      child: FittedBox(
        fit: BoxFit.scaleDown,
        alignment: compact ? Alignment.center : Alignment.centerLeft,
        child: Text(
          title,
          maxLines: 1,
          style: compact
              ? SettloTypography.headline(
                  color: SettloColors.of(context).textPrimary,
                )
              : SettloTypography.largeTitle(
                  color: SettloColors.of(context).textPrimary,
                ),
        ),
      ),
    );
    return SizedBox(
      height: 56,
      child: Stack(
        alignment: Alignment.center,
        children: [
          Positioned(
            left: compact || leading != null ? 56 : 0,
            right: 56,
            top: 4,
            bottom: 4,
            child: label,
          ),
          if (leading != null)
            Align(alignment: Alignment.centerLeft, child: leading),
          if (trailing != null)
            Align(alignment: Alignment.centerRight, child: trailing),
        ],
      ),
    );
  }
}

class _ChromeState extends InheritedWidget {
  const new({required this.compact, required super.child});
  final bool compact;
  @override
  bool updateShouldNotify(_ChromeState oldWidget) =>
      compact != oldWidget.compact;
}
