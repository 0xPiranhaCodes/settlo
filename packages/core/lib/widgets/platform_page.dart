import 'dart:async';

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
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
/// same route as [SettloPage], so Android keeps Material behaviour.
class SettloSheetPage<T> extends SettloPage<T> {
  /// Keeps the router's page identity and state restoration intact.
  const new({required super.child, super.key});

  @override
  Route<T> createRoute(BuildContext context) {
    if (Theme.of(context).platform != TargetPlatform.iOS) {
      return super.createRoute(context);
    }
    return _SheetRoute<T>(
      settings: this,
      reduced: MediaQuery.disableAnimationsOf(context),
      // The scroll scaffold inside takes this controller, so a drag down at
      // the top of the content dismisses the sheet. The surface fills the
      // corners the sheet's own frame leaves under the route's clip.
      scrollableBuilder: (context, controller) => ColoredBox(
        color: SettloColors.of(context).surface,
        child: PrimaryScrollController(controller: controller, child: child),
      ),
    );
  }
}

/// A sheet with its own navigation, such as Profile (#196): pages pushed
/// from inside with [settloPageRoute] stay in the sheet. On iOS it is
/// [SettloSheetPage]'s [CupertinoSheetRoute]; elsewhere a full-height
/// Material bottom sheet with a drag handle.
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
        showDragHandle: true,
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
      scrollableBuilder: (context, controller) => ColoredBox(
        color: c.surface,
        child: _SheetNavigator(controller: controller, child: child),
      ),
    );
  }
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

  @override
  Widget build(BuildContext context) => NavigatorPopHandler<Object?>(
    // Back pops a pushed page first; on the first page, the sheet.
    onPopWithResult: (_) => _navigator.currentState?.maybePop(),
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
    CupertinoSheetRoute.hasParentSheet(context)
    ? 0
    : MediaQuery.paddingOf(context).top.clamp(54, double.infinity);

class _SheetRoute<T> extends CupertinoSheetRoute<T> {
  new({
    required super.settings,
    required super.scrollableBuilder,
    required this.reduced,
  });
  final bool reduced;

  /// The [PopScope]s inside, read directly: [popDisposition] would recurse
  /// through [willHandlePopInternally].
  final _scopes = <PopEntry<Object?>>{};

  /// A drag down is releasing the sheet while a [PopScope] holds it, such as
  /// a form with unsaved input. The framework's drag controller pops
  /// unconditionally, and go_router ignores [didPop] unless this is true.
  bool get _dragVetoed =>
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
