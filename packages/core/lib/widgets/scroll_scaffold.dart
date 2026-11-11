import 'dart:async';

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';
import 'package:settlo_core/theme/colors.dart';
import 'package:settlo_core/theme/tokens.dart';
import 'package:settlo_core/theme/typography.dart';
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
        backgroundColor: MediaQuery.highContrastOf(context)
            ? c.surface
            : c.glass.withValues(alpha: SettloElevation.glassTint),
        border: Border(
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
    final top =
        widget.statusInset ??
        MediaQuery.paddingOf(context).top.clamp(44.0, double.infinity);
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
        if (largeTitle != null)
          _largeTitleBar(context, largeTitle)
        else
          SliverPersistentHeader(
            pinned: true,
            delegate: _NavigationHeader(
              top: top,
              forceSolid: _budget.exceeded,
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
    required this.expandedHeight,
    required this.title,
    required this.expanded,
    required this.compact,
  });
  final double top;
  final bool forceSolid;
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
    return ClipRect(
      child: Stack(
        fit: StackFit.expand,
        children: [
          if (scrolled)
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
                  color: scrolled
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
  }

  @override
  bool shouldRebuild(_NavigationHeader oldDelegate) => true;
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
