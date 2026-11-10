import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

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
    if (MediaQuery.disableAnimationsOf(context)) return child;
    final platform = Theme.of(context).platform;
    final builder =
        const PageTransitionsTheme().builders[platform] ??
        const FadeUpwardsPageTransitionsBuilder();
    return builder.buildTransitions(
      route,
      context,
      animation,
      secondaryAnimation,
      child,
    );
  }
}
