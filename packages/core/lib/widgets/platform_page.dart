import 'dart:async';

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:settlo_core/theme/colors.dart';
import 'package:settlo_core/theme/tokens.dart';

/// A routed screen with native transitions and interactive iOS back gestures.
class SettloPage<T> extends Page<T> {
  /// Keeps the router's page identity and state restoration intact.
  const new({required this.child, super.key});

  /// Page contents, including any sheet-shaped form.
  final Widget child;

  @override
  Route<T> createRoute(BuildContext context) {
    final reduced = MediaQuery.disableAnimationsOf(context);
    if (Theme.of(context).platform == TargetPlatform.iOS) {
      return _CupertinoRoute<T>(
        builder: _child,
        settings: this,
        reduced: reduced,
      );
    }
    return _MaterialRoute<T>(builder: _child, settings: this, reduced: reduced);
  }
}

/// The current page's child: a page updated in place under the same key,
/// such as a space switching segments, swaps it without a new route.
Widget _child(BuildContext context) =>
    (ModalRoute.of(context)!.settings as SettloPage<Object?>).child;

/// A full-height task sheet, such as Add expense. On iOS it is a
/// [CupertinoSheetRoute]: it slides up, scales the screen behind it into a
/// stacked card and drags down from anywhere to dismiss. Elsewhere it is the
/// full-height Material modal with the same chrome.
class SettloSheetPage<T> extends SettloPage<T> {
  /// Keeps the router's page identity and state restoration intact.
  const new({required super.child, super.key});

  @override
  Route<T> createRoute(BuildContext context) =>
      _rootSheetRoute<T>(context, _child, settings: this);
}

/// A sheet with its own navigation, such as Profile (#196): pages pushed
/// from inside with [settloPageRoute] stay in the sheet. On iOS it is
/// [SettloSheetPage]'s [CupertinoSheetRoute]; elsewhere a full-height
/// Material bottom sheet with the shared chrome.
class SettloNavigatorSheetPage<T> extends SettloPage<T> {
  /// Keeps the router's page identity and state restoration intact.
  const new({required super.child, super.key});

  @override
  Route<T> createRoute(BuildContext context) {
    final reduced = MediaQuery.disableAnimationsOf(context);
    final c = SettloColors.of(context);
    if (Theme.of(context).platform != TargetPlatform.iOS) {
      return ModalBottomSheetRoute<T>(
        settings: this,
        isScrollControlled: true,
        useSafeArea: true,
        showDragHandle: false,
        backgroundColor: c.background,
        modalBarrierColor: c.background.withValues(alpha: 0.6),
        barrierLabel: MaterialLocalizations.of(context).scrimLabel,
        clipBehavior: Clip.antiAlias,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(
            top: Radius.circular(SettloRadius.cardHero),
          ),
        ),
        sheetAnimationStyle: reduced ? AnimationStyle.noAnimation : null,
        builder: (_) => _SheetNavigator(child: child),
      );
    }
    return _SheetRoute<T>(
      settings: this,
      reduced: reduced,
      // The only entry here is the inner Back handler: a drag down closes
      // the whole sheet even with a page pushed, as a UIKit page sheet does.
      holdsDrag: false,
      scrollableBuilder: (context, controller) => ColoredBox(
        color: c.surface,
        child: _SheetNavigator(controller: controller, child: child),
      ),
    );
  }
}

/// A full-height root sheet with platform stacking and no tab bar.
Future<T?> pushSettloSheet<T>(BuildContext context, WidgetBuilder builder) {
  if (SettloSheetScope.maybeOf(context) != null) {
    return Navigator.of(context).push(settloPageRoute<T>(context, builder));
  }
  return Navigator.of(
    context,
    rootNavigator: true,
  ).push(_rootSheetRoute<T>(context, builder));
}

/// Opens a routed task inside the current sheet, preserving the route's
/// feature-owned builder. The sheet retains its URL while a nested step is
/// open; direct links still open the task on the root navigator. Outside a
/// sheet, normal router navigation applies.
Future<T?> pushSettloTask<T>(BuildContext context, String location) {
  final router = GoRouter.of(context);
  if (SettloSheetScope.maybeOf(context) != null) {
    final matches = router.configuration.findMatch(Uri.parse(location));
    if (!matches.isError) {
      final match = matches.last;
      final route = match.route;
      final state = match.buildState(
        router.configuration,
        matches,
        metadata: const {},
      );
      final page = route.pageBuilder?.call(context, state);
      if (page is SettloPage) {
        return pushSettloSheet<T>(context, (_) => page.child);
      }
    }
  }
  return router.push<T>(location);
}

/// Returns from a task step, or dismisses its root sheet.
void popSettloTask(BuildContext context, {required String fallback}) {
  final sheet = SettloSheetScope.maybeOf(context);
  if (sheet != null) {
    if (Navigator.of(context).canPop()) {
      Navigator.of(context).pop();
    } else if (GoRouter.maybeOf(context) case final router?
        when !router.canPop()) {
      router.go(fallback);
    } else {
      sheet.finish(null);
    }
  } else if (context.canPop()) {
    context.pop();
  } else {
    context.go(fallback);
  }
}

/// Completes a task with a result, including the first page of its sheet.
void finishSettloSheet(BuildContext context, [Object? result]) {
  final navigator = Navigator.of(context);
  final sheet = SettloSheetScope.maybeOf(context);
  if (sheet != null && !navigator.canPop()) {
    sheet.finish(result);
  } else {
    navigator.pop(result);
  }
}

/// Identifies the navigator owned by a root sheet.
class SettloSheetScope extends InheritedWidget {
  /// Shares the root close action with pushed steps.
  const new({
    required this.finish,
    required this.isCurrent,
    required super.child,
    super.key,
  });

  /// Completes the root sheet with its result.
  final void Function(Object?) finish;

  /// Whether the root sheet remains the active route.
  final bool Function() isCurrent;

  /// The enclosing sheet, if one exists.
  static SettloSheetScope? maybeOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<SettloSheetScope>();

  @override
  bool updateShouldNotify(SettloSheetScope oldWidget) =>
      finish != oldWidget.finish || isCurrent != oldWidget.isCurrent;
}

/// Router counterpart of [pushSettloSheet], placed on the root navigator.
typedef SettloRootSheetPage<T> = SettloSheetPage<T>;

Route<T> _rootSheetRoute<T>(
  BuildContext context,
  WidgetBuilder builder, {
  RouteSettings? settings,
}) {
  final reduced = MediaQuery.disableAnimationsOf(context);
  if (Theme.of(context).platform == TargetPlatform.iOS) {
    return _SheetRoute<T>(
      settings: settings,
      reduced: reduced,
      scrollableBuilder: (context, controller) => ColoredBox(
        color: SettloColors.of(context).background,
        child: PrimaryScrollController(
          controller: controller,
          child: _SheetNavigator(
            controller: controller,
            child: settings is SettloPage
                ? _child(context)
                : Builder(builder: builder),
          ),
        ),
      ),
    );
  }
  return ModalBottomSheetRoute<T>(
    settings: settings,
    isScrollControlled: true,
    useSafeArea: true,
    showDragHandle: false,
    backgroundColor: SettloColors.of(context).background,
    barrierLabel: MaterialLocalizations.of(context).scrimLabel,
    sheetAnimationStyle: reduced ? AnimationStyle.noAnimation : null,
    builder: (context) => Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: MediaQuery.removeViewInsets(
        context: context,
        removeBottom: true,
        child: SizedBox.expand(
          child: _SheetNavigator(
            child: settings is SettloPage
                ? _child(context)
                : Builder(builder: builder),
          ),
        ),
      ),
    ),
  );
}

/// A page pushed inside a [SettloNavigatorSheetPage], with the platform's
/// transition and back gesture.
Route<T> settloPageRoute<T>(BuildContext context, WidgetBuilder builder) {
  final reduced = MediaQuery.disableAnimationsOf(context);
  return Theme.of(context).platform == TargetPlatform.iOS
      ? _CupertinoRoute<T>(builder: builder, settings: null, reduced: reduced)
      : _MaterialRoute<T>(builder: builder, settings: null, reduced: reduced);
}

class _SheetNavigator extends StatefulWidget {
  const new({required this.child, this.controller});

  final Widget child;

  /// The sheet's drag-to-dismiss controller, for the first page only.
  final ScrollController? controller;

  @override
  State<_SheetNavigator> createState() => _SheetNavigatorState();
}

class _SheetNavigatorState extends State<_SheetNavigator> {
  final _navigator = GlobalKey<NavigatorState>();

  void _finish(Object? result) => Navigator.of(context).pop(result);
  bool _isCurrent() => ModalRoute.of(context)?.isCurrent ?? false;

  @override
  Widget build(BuildContext context) => NavigatorPopHandler<Object?>(
    // Back pops a pushed page first; on the first page, the sheet.
    onPopWithResult: (_) => _navigator.currentState?.maybePop(),
    child: SettloSheetScope(
      finish: _finish,
      isCurrent: _isCurrent,
      child: Navigator(
        key: _navigator,
        onGenerateInitialRoutes: (_, _) => [
          settloPageRoute<void>(
            context,
            // Each route has its own primary controller; give the first page
            // the sheet's back so a drag down at the top dismisses it.
            (_) => widget.controller == null
                ? widget.child
                : PrimaryScrollController(
                    controller: widget.controller!,
                    child: widget.child,
                  ),
          ),
        ],
      ),
    ),
  );
}

/// Shows [builder] as a full-height page sheet, such as Create space, on
/// the root navigator. On iOS it is the same route as [SettloSheetPage]:
/// a [PopScope] inside holds a drag down. Elsewhere it is [fallback], so
/// Android keeps its Material sheet.
Future<T?> showSettloPageSheet<T>({
  required BuildContext context,
  required WidgetBuilder builder,
  required Future<T?> Function() fallback,
}) {
  if (Theme.of(context).platform != TargetPlatform.iOS) return fallback();
  return Navigator.of(context, rootNavigator: true).push(
    _SheetRoute<T>(
      settings: null,
      reduced: MediaQuery.disableAnimationsOf(context),
      scrollableBuilder: (context, controller) => ColoredBox(
        color: SettloColors.of(context).surface,
        child: PrimaryScrollController(
          controller: controller,
          child: Builder(builder: builder),
        ),
      ),
    ),
  );
}

/// How far a sheet-shaped screen sits below the top of the screen: 54 as on
/// the canvas, or nothing inside a [SettloSheetPage] on iOS, whose route
/// already leaves the gap.
double settloSheetTop(BuildContext context) =>
    (CupertinoSheetRoute.hasParentSheet(context) ||
        SettloSheetScope.maybeOf(context) != null)
    ? 0
    : MediaQuery.paddingOf(context).top.clamp(54, double.infinity);

class _SheetRoute<T> extends CupertinoSheetRoute<T> {
  new({
    required super.settings,
    required super.scrollableBuilder,
    required this.reduced,
    this.holdsDrag = true,
  });
  final bool reduced;

  /// Whether a [PopScope] inside can hold a drag down.
  final bool holdsDrag;

  /// The [PopScope]s inside, read directly: [popDisposition] would recurse
  /// through [willHandlePopInternally].
  final _scopes = <PopEntry<Object?>>{};

  /// A drag down is releasing the sheet while a [PopScope] holds it, such as
  /// a form with unsaved input. The framework's drag controller pops
  /// unconditionally, and go_router ignores [didPop] unless this is true.
  bool get _dragVetoed =>
      holdsDrag &&
      (navigator?.userGestureInProgress ?? false) &&
      _scopes.any((s) => !s.canPopNotifier.value);

  @override
  void registerPopEntry(PopEntry<Object?> popEntry) {
    super.registerPopEntry(popEntry);
    _scopes.add(popEntry);
  }

  @override
  void unregisterPopEntry(PopEntry<Object?> popEntry) {
    _scopes.remove(popEntry);
    super.unregisterPopEntry(popEntry);
  }

  @override
  bool get willHandlePopInternally =>
      _dragVetoed || super.willHandlePopInternally;

  @override
  bool didPop(T? result) {
    if (!_dragVetoed) return super.didPop(result);
    // After the drag ends and the navigator unlocks: snap the sheet back up
    // and let the PopScope ask.
    scheduleMicrotask(() {
      if (!isActive) return;
      if (reduced) {
        controller?.value = 1;
      } else {
        controller?.animateTo(1, duration: const Duration(milliseconds: 300));
      }
      onPopInvokedWithResult(false, result);
    });
    return false;
  }

  @override
  Duration get transitionDuration =>
      reduced ? Duration.zero : super.transitionDuration;
  @override
  Duration get reverseTransitionDuration =>
      reduced ? Duration.zero : super.reverseTransitionDuration;
}

class _CupertinoRoute<T> extends CupertinoPageRoute<T> {
  new({required super.builder, required super.settings, required this.reduced});
  final bool reduced;
  @override
  Duration get transitionDuration =>
      reduced ? Duration.zero : super.transitionDuration;
  @override
  Duration get reverseTransitionDuration =>
      reduced ? Duration.zero : super.reverseTransitionDuration;
}

class _MaterialRoute<T> extends MaterialPageRoute<T> {
  new({required super.builder, required super.settings, required this.reduced});
  final bool reduced;
  @override
  Duration get transitionDuration =>
      reduced ? Duration.zero : super.transitionDuration;
  @override
  Duration get reverseTransitionDuration =>
      reduced ? Duration.zero : super.reverseTransitionDuration;
}

/// Retains Flutter's native page transitions, suppressing motion on request.
class SettloPageTransitionsBuilder extends PageTransitionsBuilder {
  /// Applies to regular router pages as well as explicitly constructed pages.
  const new();

  @override
  Widget buildTransitions<T>(
    PageRoute<T> route,
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
    Widget child,
  ) {
    final reduced = MediaQuery.disableAnimationsOf(context);
    final platform = Theme.of(context).platform;
    final builder =
        const PageTransitionsTheme().builders[platform] ??
        const FadeUpwardsPageTransitionsBuilder();
    // Cupertino's builder also owns the edge-swipe detector. Keep it installed
    // under Reduce Motion; suppress automatic movement, not user-driven swipes.
    if (reduced && platform != TargetPlatform.iOS) return child;
    final interactive = route.popGestureInProgress;
    return builder.buildTransitions(
      route,
      context,
      reduced && !interactive ? const AlwaysStoppedAnimation(1) : animation,
      reduced && !interactive
          ? const AlwaysStoppedAnimation(0)
          : secondaryAnimation,
      child,
    );
  }
}
