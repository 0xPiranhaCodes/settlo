import 'package:flutter/material.dart';
import 'package:settlo_core/theme/colors.dart';
import 'package:settlo_core/theme/tokens.dart';

/// Shows [builder] as a Settlo modal bottom sheet. Every sheet in the app
/// opens through this.
///
/// It is presented on the root navigator, above the shell, so the floating
/// tab bar never covers the sheet or takes its taps (#81), and it sits
/// above the keyboard. The sheet's content keeps clear of the device's
/// bottom inset with a `SafeArea(top: false)`, so its background still
/// reaches the bottom edge. [backgroundColor]
/// defaults to the surface with rounded top corners; a sheet that draws
/// its own frame, like `SAmountSheet`, passes transparent.
Future<T?> showSettloSheet<T>({
  required BuildContext context,
  required WidgetBuilder builder,
  Color? backgroundColor,
  bool showDragHandle = true,
}) {
  final c = SettloColors.of(context);
  return showModalBottomSheet<T>(
    context: context,
    useRootNavigator: true,
    showDragHandle: false,
    sheetAnimationStyle: MediaQuery.disableAnimationsOf(context)
        ? AnimationStyle.noAnimation
        : const AnimationStyle(
            duration: SettloMotion.panel,
            reverseDuration: SettloMotion.panel,
          ),
    isScrollControlled: true,
    useSafeArea: true,
    backgroundColor: Colors.transparent,
    barrierColor: c.background.withValues(alpha: 0.6),
    elevation: 0,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(
        top: Radius.circular(SettloRadius.cardHero),
      ),
    ),
    builder: (context) => Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: Container(
        decoration: backgroundColor == Colors.transparent
            ? null
            : BoxDecoration(
                color: backgroundColor ?? c.surface,
                borderRadius: const BorderRadius.vertical(
                  top: Radius.circular(SettloRadius.cardHero),
                ),
                border: Border.all(
                  color: SettloElevation.border(
                    dark: Theme.of(context).brightness == Brightness.dark,
                  ),
                ),
                boxShadow: SettloElevation.ambient(
                  dark: Theme.of(context).brightness == Brightness.dark,
                ),
              ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (showDragHandle)
              Padding(
                padding: const EdgeInsets.only(top: 12, bottom: 4),
                child: Center(
                  child: Container(
                    width: 36,
                    height: 4,
                    decoration: BoxDecoration(
                      color: c.textMuted,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
              ),
            Flexible(child: builder(context)),
          ],
        ),
      ),
    ),
  );
}
