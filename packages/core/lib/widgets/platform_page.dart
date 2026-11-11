import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:settlo_core/theme/colors.dart';

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
        builder: (_) => child,
        settings: this,
        reduced: reduced,
      );
    }
    return _MaterialRoute<T>(
      builder: (_) => child,
      settings: this,
      reduced: reduced,
    );
  }
}

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
