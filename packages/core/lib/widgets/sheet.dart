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
}) {
  final c = SettloColors.of(context);
  return showModalBottomSheet<T>(
    context: context,
    useRootNavigator: true,
    sheetAnimationStyle: MediaQuery.disableAnimationsOf(context)
        ? AnimationStyle.noAnimation
        : const AnimationStyle(
            duration: SettloMotion.panel,
            reverseDuration: SettloMotion.panel,
          ),
    isScrollControlled: true,
    useSafeArea: true,
    backgroundColor: backgroundColor ?? c.surface,
    barrierColor: c.background.withValues(alpha: 0.6),
    elevation: 0,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(
        top: Radius.circular(SettloRadius.cardHero),
      ),
    ),
    builder: (context) => Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: builder(context),
    ),
  );
}
