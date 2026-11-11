import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:settlo/native_tab_bar.dart';
import 'package:settlo_core/settlo_core.dart';

/// The four tabs, in canvas order.
final List<SGlassTab> _tabs = [
  (icon: STabIcon.home.widget, label: 'Home'),
  (icon: STabIcon.spaces.widget, label: 'Spaces'),
  (icon: STabIcon.loans.widget, label: 'Loans'),
  (icon: STabIcon.activity.widget, label: 'Activity'),
];

/// The same tabs as SF Symbols, for the system tab bar on iOS.
final List<NativeTab> _nativeTabs = [
  for (final (i, symbol) in const [
    'house',
    'person.2',
    'banknote',
    'waveform.path.ecg',
  ].indexed)
    (label: _tabs[i].label, symbol: symbol),
];

/// Hosts a tab's screen with the floating glass tab bar over it, 20px from
/// each side and 22px above the bottom edge as on the canvas.
///
/// The bar is reported to the tab's screen as a bottom system inset
/// (`MediaQuery.padding` and `viewPadding`), so `SafeArea` keeps fixed
/// content clear of it and scroll views pad their last item above it while
/// rows still scroll under the glass.
///
/// On iOS the bar is the system UITabBar ([NativeTabBar]) across the bottom
/// edge, and the inset is the height UIKit reports for it.
class SettloShell extends StatefulWidget {
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
  State<SettloShell> createState() => _SettloShellState();
}

class _SettloShellState extends State<SettloShell> {
  final _scrolls = SettloScrollRegistry();
  double? _nativeHeight;

  void _select(int index) {
    if (index == widget.currentIndex && _scrolls.scrollToTop()) return;
    if (index != widget.currentIndex) unawaited(HapticFeedback.lightImpact());
    widget.onTabSelected(index);
  }

  @override
  Widget build(BuildContext context) {
    final media = MediaQuery.of(context);
    final theme = Theme.of(context);
    if (theme.platform == TargetPlatform.iOS) {
      final height = _nativeHeight ?? nativeTabBarFallbackHeight(media);
      return _scaffold(
        media,
        height,
        Positioned(
          left: 0,
          right: 0,
          bottom: 0,
          height: height,
          child: NativeTabBar(
            tabs: _nativeTabs,
            currentIndex: widget.currentIndex,
            dark: theme.brightness == Brightness.dark,
            onTap: _select,
            onHeight: (h) {
              if (h != _nativeHeight) setState(() => _nativeHeight = h);
            },
          ),
        ),
      );
    }
    // The canvas's 22px assumes the 34px iPhone home indicator; keep the bar
    // clear of taller system navigation (e.g. Android three-button).
    final bottom = math.max<double>(22, media.viewPadding.bottom - 12);
    final inset =
        bottom + SGlassTabBar.heightFor(media.textScaler) + SettloSpacing.x1;
    return _scaffold(
      media,
      inset,
      Positioned(
        left: SettloSpacing.screenMargin,
        right: SettloSpacing.screenMargin,
        bottom: bottom,
        child: SGlassTabBar(
          tabs: _tabs,
          currentIndex: widget.currentIndex,
          onTap: _select,
          lowEndBlur: widget.flatChrome,
        ),
      ),
    );
  }

  Widget _scaffold(MediaQueryData media, double inset, Widget bar) => Scaffold(
    body: Stack(
      children: [
        Positioned.fill(
          child: MediaQuery(
            data: media.copyWith(
              padding: media.padding.copyWith(bottom: inset),
              viewPadding: media.viewPadding.copyWith(bottom: inset),
            ),
            child: SettloScrollScope(registry: _scrolls, child: widget.child),
          ),
        ),
        bar,
      ],
    ),
  );
}
