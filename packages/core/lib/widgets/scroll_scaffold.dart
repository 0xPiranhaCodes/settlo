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
import 'package:settlo_core/widgets/sheet_header.dart';

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

/// Shared sliver chrome. By default, the first child is the expanded header.
/// Task sheets supply [onSheetClose] and use every child as list content.
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
    this.stickyHeader = true,
    this.onSheetClose,
    this.tabRoot = false,
    super.key,
  });

  /// Compact navigation title, also used as the scroll-position identity.
  final String title;

  /// Uses the shared large-title tab chrome.
  final bool tabRoot;

  /// Expanded header first, then page content; task sheets supply only content.
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

  /// False on tab roots (#197): the header scrolls away with the content,
  /// and only a mild blur stays behind the status bar.
  final bool stickyHeader;

  /// A task sheet owns its fixed title and close control.
  /// All children are content.
  final VoidCallback? onSheetClose;

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
    final route = ModalRoute.of(context);
    final destination =
        widget.previousPageTitle ??
        (route is CupertinoRouteTransitionMixin
            ? route.previousTitle.value
            : null);
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
        leading: route?.canPop ?? false
            ? GlassAction.back(
                destination: destination,
                onPressed: () => Navigator.of(context).maybePop(),
              )
            : null,
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
      physics: widget.onSheetClose != null
          ? (ios
                ? const _TopClampedScrollPhysics(
                    parent: AlwaysScrollableScrollPhysics(),
                  )
                : const ClampingScrollPhysics(
                    parent: AlwaysScrollableScrollPhysics(),
                  ))
          : const SettloScrollBehavior().getScrollPhysics(context),
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
                solid: false,
              ),
            ),
          ),
        if (widget.onSheetClose case final close?)
          SliverPersistentHeader(
            pinned: true,
            delegate: _TaskSheetHeader(title: widget.title, onClose: close),
          ),
        if (widget.tabRoot)
          SliverPersistentHeader(
            pinned: true,
            delegate: _TabHeader(
              top: top,
              title: widget.title,
              actions: header is SettloNavigationHeader
                  ? header.trailing
                  : header,
              scale: MediaQuery.textScalerOf(context).scale(34) / 34,
            ),
          ),
        if (!widget.tabRoot &&
            largeTitle == null &&
            widget.onSheetClose == null)
          SliverPersistentHeader(
            pinned: true,
            delegate: _NavigationHeader(
              top: top,
              sticky: widget.stickyHeader,
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
            sliver: SliverList.list(
              children: widget.onSheetClose == null
                  ? widget.children.skip(1).toList()
                  : widget.children,
            ),
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

/// Part of the same viewport as the list: a header drag goes to its scroll
/// position before the Cupertino route can move, including when pinned.
class _TaskSheetHeader extends SliverPersistentHeaderDelegate {
  new({required this.title, required this.onClose});
  final String title;
  final VoidCallback onClose;

  @override
  double get minExtent => SSheetHeader.extent;
  @override
  double get maxExtent => minExtent;

  @override
  Widget build(
    BuildContext context,
    double shrinkOffset,
    bool overlapsContent,
  ) {
    return SSheetHeader(
      key: const ValueKey('task-sheet-header'),
      title: title,
      onClose: onClose,
      scrolledUnder: overlapsContent || shrinkOffset > 0,
    );
  }

  @override
  bool shouldRebuild(_TaskSheetHeader oldDelegate) =>
      title != oldDelegate.title || onClose != oldDelegate.onClose;
}

class _NavigationHeader extends SliverPersistentHeaderDelegate {
  new({
    required this.top,
    required this.sticky,
    required this.forceSolid,
    required this.glass,
    required this.expandedHeight,
    required this.title,
    required this.expanded,
    required this.compact,
  });
  final double top;

  /// See [SettloScrollScaffold.stickyHeader].
  final bool sticky;
  final bool forceSolid;

  /// iOS 26: a soft scroll edge instead of the band, strip and plate.
  final bool glass;
  final double expandedHeight;
  final String title;
  final Widget expanded;
  final Widget compact;

  @override
  double get minExtent => sticky ? top + 56 : top;
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
    if (!sticky) {
      return Stack(
        clipBehavior: Clip.none,
        fit: StackFit.expand,
        children: [
          Positioned(
            left: 20,
            right: 20,
            top: top - shrinkOffset,
            height: expandedHeight - 24,
            child: Center(
              // The status bar's blur can't reach native views, so the
              // glass actions scroll with the title and are clipped only
              // where they enter it (#197).
              child: GlassActionInset(
                inset: top,
                child: SizedBox(
                  width: double.infinity,
                  child: DefaultTextStyle.merge(
                    style: SettloTypography.title2(color: c.textPrimary),
                    child: expanded,
                  ),
                ),
              ),
            ),
          ),
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            height: top + _statusFeather,
            child: _StatusEdge(
              strength: (shrinkOffset / 16).clamp(0.0, 1.0),
              inset: top,
              color: solid ? c.surface : c.background,
              blur: !solid && Theme.of(context).platform == TargetPlatform.iOS,
              solid: solid,
            ),
          ),
        ],
      );
    }
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
            solid: solid,
          ),
        ),
        bar,
      ],
    );
  }

  @override
  bool shouldRebuild(_NavigationHeader oldDelegate) => true;
}

/// How far below the bar the iOS 26 edge fades out.
const _softEdgeFade = 32.0;

/// iOS 26's soft scroll edge (#191): a page-colour scrim, strongest under the
/// status bar and easing out to nothing below the bar, with no band, plate or
/// hairline. [strength] scales the whole edge from none to full. No blur:
/// Impeller can't mask a BackdropFilter, so a clipped blur always ends on a
/// visible line.
class _SoftEdge extends StatelessWidget {
  const new({required this.strength, required this.color, required this.solid});

  final double strength;
  final Color color;

  /// Opaque down to the bar's bottom, for high contrast and slow devices.
  final bool solid;

  @override
  Widget build(BuildContext context) => strength == 0
      ? const SizedBox.expand()
      : LayoutBuilder(
          builder: (context, box) =>
              _edge((box.maxHeight - _softEdgeFade) / box.maxHeight),
        );

  /// From `top` at the status bar to `bar` at [full] of the height, then
  /// easing out to 0, so the fade has no visible start or end.
  Widget _edge(double full) {
    final (top, bar) = solid ? (1.0, 1.0) : (0.94, 0.9);
    final tail = [for (var i = 1; i <= 6; i++) i / 6];
    return DecoratedBox(
      key: const ValueKey('scroll-navigation-soft-edge'),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            color.withValues(alpha: top * strength),
            color.withValues(alpha: bar * strength),
            for (final t in tail)
              color.withValues(
                alpha: bar * strength * (1 - Curves.easeInOut.transform(t)),
              ),
          ],
          stops: [0, full, for (final t in tail) full + (1 - full) * t],
        ),
      ),
    );
  }
}

/// How far below the status bar the tab roots' edge eases out.
const _statusFeather = 10.0;

/// The tab roots' status bar (#197): on iOS a mild blur down to the top
/// [inset] under a page-colour veil, elsewhere the veil alone, easing out
/// over [_statusFeather] below it. The veil runs past the blur's clipped
/// edge, which Impeller can't mask (#195), so no line shows where it ends.
class _StatusEdge extends StatelessWidget {
  const new({
    required this.strength,
    required this.inset,
    required this.color,
    required this.blur,
    required this.solid,
  });

  /// From none at rest to full once content is under the status bar.
  final double strength;
  final double inset;
  final Color color;
  final bool blur;

  /// Opaque, for high contrast and slow devices.
  final bool solid;

  @override
  Widget build(BuildContext context) {
    if (strength == 0) return const SizedBox.expand();
    final veil = strength * (solid ? 1 : 0.9);
    final full = inset / (inset + _statusFeather);
    final tail = [for (var i = 1; i <= 4; i++) i / 4];
    return Stack(
      fit: StackFit.expand,
      children: [
        if (blur)
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            height: inset,
            child: ClipRect(
              child: BackdropFilter(
                filter: ImageFilter.blur(
                  sigmaX: 8 * strength,
                  sigmaY: 8 * strength,
                ),
                child: const SizedBox.expand(),
              ),
            ),
          ),
        DecoratedBox(
          key: const ValueKey('scroll-status-edge'),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [
                color.withValues(alpha: veil),
                color.withValues(alpha: veil),
                for (final t in tail)
                  color.withValues(
                    alpha: veil * (1 - Curves.easeInOut.transform(t)),
                  ),
              ],
              stops: [0, full, for (final t in tail) full + (1 - full) * t],
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
    // One tree whether compact or not, so a native trailing action is never
    // rebuilt; the title gets what the actions leave, up to three (#197).
    return SizedBox(
      height: 56,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SizedBox(
            width: compact || leading != null ? 56 : 0,
            child: Align(alignment: Alignment.centerLeft, child: leading),
          ),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: label,
            ),
          ),
          if (trailing case final trailing?) ...[
            const SizedBox(width: 12),
            Center(child: trailing),
          ] else
            const SizedBox(width: 56),
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

/// The pinned header stays fixed at the top; the trailing edge still bounces.
class _TopClampedScrollPhysics extends BouncingScrollPhysics {
  const new({super.parent});
  @override
  _TopClampedScrollPhysics applyTo(ScrollPhysics? ancestor) =>
      _TopClampedScrollPhysics(parent: buildParent(ancestor));
  @override
  double applyBoundaryConditions(ScrollMetrics position, double value) {
    if (value < position.minScrollExtent) {
      return value -
          (position.pixels < position.minScrollExtent
              ? position.pixels
              : position.minScrollExtent);
    }
    return 0;
  }
}

/// Shared tab spacing and large-title behavior, independent of sheet chrome.
class SettloTabScaffold extends StatelessWidget {
  /// The first child supplies header actions; the rest is scroll content.
  const new({
    required this.title,
    required this.children,
    this.onRefresh,
    this.controller,
    this.slivers,
    super.key,
  });

  /// Tab name.
  final String title;

  /// Header followed by content.
  final List<Widget> children;

  /// Pull to refresh.
  final Future<void> Function()? onRefresh;

  /// Optional pagination controller.
  final ScrollController? controller;

  /// Optional grouped slivers with pinned section labels.
  final List<Widget>? slivers;

  /// Shared content inset and title gap.
  static const double inset = 16;

  /// Space between independent groups.
  static const double groupGap = 32;
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final c = SettloColors.of(context);
    const shape = WidgetStatePropertyAll<OutlinedBorder>(
      RoundedRectangleBorder(
        borderRadius: BorderRadius.all(Radius.circular(14)),
      ),
    );
    return Theme(
      data: theme.copyWith(
        filledButtonTheme: FilledButtonThemeData(
          style: (theme.filledButtonTheme.style ?? const ButtonStyle())
              .copyWith(shape: shape),
        ),
        outlinedButtonTheme: OutlinedButtonThemeData(
          style: (theme.outlinedButtonTheme.style ?? const ButtonStyle())
              .copyWith(
                shape: shape,
                side: const WidgetStatePropertyAll(BorderSide.none),
                backgroundColor: WidgetStatePropertyAll(
                  c.action.withValues(alpha: .1),
                ),
              ),
        ),
      ),
      child: NeutralGlassActions(
        child: SettloScrollScaffold(
          title: title,
          tabRoot: true,
          slivers: slivers,
          controller: controller,
          onRefresh: onRefresh,
          headerGap: inset,
          padding: EdgeInsets.fromLTRB(
            inset,
            0,
            inset,
            MediaQuery.paddingOf(context).bottom + inset,
          ),
          children: children,
        ),
      ),
    );
  }
}

class _TabHeader extends SliverPersistentHeaderDelegate {
  new({
    required this.top,
    required this.title,
    required this.actions,
    required this.scale,
  });
  final double top;
  final String title;
  final Widget? actions;
  final double scale;
  @override
  double get minExtent => top + 56;
  @override
  double get maxExtent => minExtent + 34 * scale * 1.2 + 8;
  @override
  Widget build(
    BuildContext context,
    double shrinkOffset,
    bool overlapsContent,
  ) {
    final c = SettloColors.of(context);
    final progress = (shrinkOffset / (maxExtent - minExtent)).clamp(0.0, 1.0);
    final scrolled = overlapsContent || shrinkOffset > maxExtent - minExtent;
    return ClipRect(
      child: BackdropFilter(
        enabled: scrolled && !MediaQuery.highContrastOf(context),
        filter: ImageFilter.blur(sigmaX: 30, sigmaY: 30),
        child: ColoredBox(
          key: const ValueKey('tab-header-material'),
          color: scrolled && !MediaQuery.highContrastOf(context)
              ? c.background.withValues(alpha: .8)
              : c.background,
          child: Stack(
            children: [
              Positioned(
                top: top,
                left: 16,
                right: 16,
                height: 56,
                child: Row(
                  children: [
                    const Expanded(child: SizedBox.shrink()),
                    ?actions,
                  ],
                ),
              ),
              // Shrink before entering the action band; the shallow arc keeps
              // accessibility titles clear of the trailing controls throughout.
              Positioned(
                left: 16,
                right: 16,
                top:
                    top +
                    56 * (1 - progress) +
                    (56 - 17 * scale * 1.2) / 2 * progress +
                    28 * progress * (1 - progress),
                child: IgnorePointer(
                  child: Semantics(
                    header: true,
                    child: Text(
                      title,
                      style: TextStyle.lerp(
                        SettloTypography.largeTitle(
                          color: c.textPrimary,
                          weight: FontWeight.w700,
                        ).copyWith(height: 1.2),
                        SettloTypography.headline(color: c.textPrimary)
                            .copyWith(height: 1.2),
                        Curves.easeOut.transform(progress),
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
  }

  @override
  bool shouldRebuild(_TabHeader oldDelegate) =>
      top != oldDelegate.top ||
      title != oldDelegate.title ||
      actions != oldDelegate.actions ||
      scale != oldDelegate.scale;
}
