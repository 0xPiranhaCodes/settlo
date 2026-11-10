import 'dart:ui' show ImageFilter;

import 'package:flutter/material.dart';
import 'package:settlo_core/theme/colors.dart';
import 'package:settlo_core/theme/tokens.dart';
import 'package:settlo_core/widgets/pressable.dart';

/// One destination in an [SGlassTabBar].
typedef SGlassTab = ({Widget icon, String label});

/// The floating tab bar: a 68px pill of frosted glass (28px blur, 62%
/// surface, 1px specular border) that floats over content. Glass is for
/// chrome only; never blur behind content or amounts.
///
/// Where blur is too costly (mid-range Android), set [lowEndBlur] to draw
/// a flat 92% surface instead (canvas note n32).
class SGlassTabBar extends StatelessWidget {
  /// A bar over [tabs] with [currentIndex] selected.
  const new({
    required this.tabs,
    required this.currentIndex,
    required this.onTap,
    this.lowEndBlur = false,
    super.key,
  });

  /// The destinations, in order.
  final List<SGlassTab> tabs;

  /// Index of the selected tab.
  final int currentIndex;

  /// Called with the tapped tab's index.
  final ValueChanged<int> onTap;

  /// Whether to skip the blur and use the flat fallback surface.
  final bool lowEndBlur;

  @override
  Widget build(BuildContext context) {
    final c = SettloColors.of(context);
    final dark = Theme.of(context).brightness == Brightness.dark;
    const radius = BorderRadius.all(
      Radius.circular(SettloElevation.tabBarHeight / 2),
    );
    final bar = Container(
      height: SettloElevation.tabBarHeight,
      padding: const EdgeInsets.symmetric(horizontal: 10),
      decoration: BoxDecoration(
        color: lowEndBlur ? c.glassFallback : c.glass,
        borderRadius: radius,
        border: Border.all(color: c.glassBorder),
      ),
      child: Row(
        children: [
          for (final (i, tab) in tabs.indexed)
            Expanded(
              child: _Tab(
                tab: tab,
                selected: i == currentIndex,
                onTap: () => onTap(i),
              ),
            ),
        ],
      ),
    );
    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: radius,
        boxShadow: dark
            ? SettloElevation.floatingDark
            : SettloElevation.floatingLight,
      ),
      child: ClipRRect(
        borderRadius: radius,
        child: lowEndBlur
            ? bar
            : BackdropFilter(
                // CSS `blur(28px)` is a standard deviation, as is sigma.
                filter: ImageFilter.blur(
                  sigmaX: SettloElevation.glassBlur,
                  sigmaY: SettloElevation.glassBlur,
                ),
                child: bar,
              ),
      ),
    );
  }
}

class _Tab extends StatelessWidget {
  const new({required this.tab, required this.selected, required this.onTap});

  final SGlassTab tab;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = SettloColors.of(context);
    final color = selected ? SettloColors.dark.onAction : c.textMuted;
    return SPressable(
      onTap: onTap,
      selected: selected,
      label: tab.label,
      ringRadius: BorderRadius.circular(26),
      child: Container(
        height: 52,
        decoration: BoxDecoration(
          color: selected ? c.welcomeAction : null,
          borderRadius: BorderRadius.circular(26),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            IconTheme.merge(
              data: IconThemeData(color: color, size: 22),
              child: tab.icon,
            ),
            const SizedBox(height: 3),
            Text(
              tab.label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.labelSmall
                  ?.copyWith(color: color, height: 1.1),
            ),
          ],
        ),
      ),
    );
  }
}
