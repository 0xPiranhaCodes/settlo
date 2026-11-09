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

/// Hosts a tab's screen with the floating glass tab bar over it, 16px from
/// each side and 22px above the bottom edge as on the canvas.
class SettloShell extends StatelessWidget {
  /// A shell showing [child] with tab [currentIndex] selected.
  const new({
    required this.currentIndex,
    required this.onTabSelected,
    required this.child,
    super.key,
  });

  /// The selected tab.
  final int currentIndex;

  /// Called with the tapped tab's index.
  final ValueChanged<int> onTabSelected;

  /// The current tab's screen.
  final Widget child;

  @override
  Widget build(BuildContext context) {
    // The canvas's 22px assumes the 34px iPhone home indicator; keep the bar
    // clear of taller system navigation (e.g. Android three-button).
    final bottom = math.max<double>(
      22,
      MediaQuery.viewPaddingOf(context).bottom - 12,
    );
    return Scaffold(
      body: Stack(
        children: [
          Positioned.fill(child: child),
          Positioned(
            left: 16,
            right: 16,
            bottom: bottom,
            child: SGlassTabBar(
              tabs: _tabs,
              currentIndex: currentIndex,
              onTap: onTabSelected,
            ),
          ),
        ],
      ),
    );
  }
}
