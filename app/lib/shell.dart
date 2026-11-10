import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:settlo_core/settlo_core.dart';

/// The four tabs, in canvas order.
final List<SGlassTab> _tabs = [
  (icon: STabIcon.home.widget, label: 'Home'),
  (icon: STabIcon.spaces.widget, label: 'Spaces'),
  (icon: STabIcon.loans.widget, label: 'Loans'),
  (icon: STabIcon.activity.widget, label: 'Activity'),
];

/// Hosts a tab's screen with the floating glass tab bar over it, 20px from
/// each side and 22px above the bottom edge as on the canvas.
///
/// The bar is reported to the tab's screen as a bottom system inset
/// (`MediaQuery.padding` and `viewPadding`), so `SafeArea` keeps fixed
/// content clear of it and scroll views pad their last item above it while
/// rows still scroll under the glass.
class SettloShell extends StatelessWidget {
  /// A shell showing [child] with tab [currentIndex] selected.
  const new({
    required this.currentIndex,
    required this.onTabSelected,
    required this.child,
    this.flatChrome = false,
    super.key,
  });

  /// The selected tab.
  final int currentIndex;

  /// Called with the tapped tab's index.
  final ValueChanged<int> onTabSelected;

  /// The current tab's screen.
  final Widget child;

  /// Draw the tab bar's opaque surface instead of glass (n32).
  final bool flatChrome;

  @override
  Widget build(BuildContext context) {
    // The canvas's 22px assumes the 34px iPhone home indicator; keep the bar
    // clear of taller system navigation (e.g. Android three-button).
    final media = MediaQuery.of(context);
    final bottom = math.max<double>(22, media.viewPadding.bottom - 12);
    final inset =
        bottom + SGlassTabBar.heightFor(media.textScaler) + SettloSpacing.x1;
    return Scaffold(
      body: Stack(
        children: [
          Positioned.fill(
            child: MediaQuery(
              data: media.copyWith(
                padding: media.padding.copyWith(bottom: inset),
                viewPadding: media.viewPadding.copyWith(bottom: inset),
              ),
              child: child,
            ),
          ),
          Positioned(
            left: SettloSpacing.screenMargin,
            right: SettloSpacing.screenMargin,
            bottom: bottom,
            child: SGlassTabBar(
              tabs: _tabs,
              currentIndex: currentIndex,
              onTap: onTabSelected,
              lowEndBlur: flatChrome,
            ),
          ),
        ],
      ),
    );
  }
}
