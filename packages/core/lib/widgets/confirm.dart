import 'package:flutter/cupertino.dart';
import 'package:settlo_core/theme/colors.dart';

/// Asks with a native [CupertinoActionSheet], for a destructive choice
/// started from a button, such as signing out. True when [destructive] is
/// chosen, false for [cancel], null when dismissed. iOS only.
Future<bool?> showSettloActionSheet({
  required BuildContext context,
  required String destructive,
  required String cancel,
  String? title,
  String? message,
}) => showSettloPopup<bool>(
  context: context,
  builder: (context) => _Tinted(
    child: CupertinoActionSheet(
      title: title == null ? null : Text(title),
      message: message == null ? null : Text(message),
      actions: [
        CupertinoActionSheetAction(
          isDestructiveAction: true,
          onPressed: () => _answer(context, true),
          child: Text(destructive),
        ),
      ],
      cancelButton: CupertinoActionSheetAction(
        isDefaultAction: true,
        onPressed: () => _answer(context, false),
        child: Text(cancel),
      ),
    ),
  ),
);

/// Shows [builder] from the bottom of the screen, as
/// [showCupertinoModalPopup] does: action sheets and pickers. Under Reduce
/// Motion it appears in place.
Future<T?> showSettloPopup<T>({
  required BuildContext context,
  required WidgetBuilder builder,
}) => Navigator.of(context, rootNavigator: true).push(
  _Popup<T>(
    barrierColor: CupertinoDynamicColor.resolve(
      kCupertinoModalBarrierColor,
      context,
    ),
    reduced: MediaQuery.disableAnimationsOf(context),
    builder: builder,
  ),
);

/// Asks with a native [CupertinoAlertDialog], for an irreversible choice
/// such as deleting the account. True when [destructive] is chosen, false
/// for [cancel]. iOS only.
Future<bool?> showSettloAlert({
  required BuildContext context,
  required String title,
  required String message,
  required String destructive,
  required String cancel,
}) => Navigator.of(context, rootNavigator: true).push(
  CupertinoDialogRoute<bool>(
    context: context,
    // Reduce Motion: no scale, only the barrier fades.
    transitionBuilder: MediaQuery.disableAnimationsOf(context)
        ? (_, _, _, child) => child
        : null,
    builder: (context) => _Tinted(
      child: CupertinoAlertDialog(
        title: Text(title),
        content: Text(message),
        actions: [
          CupertinoDialogAction(
            isDefaultAction: true,
            onPressed: () => _answer(context, false),
            child: Text(cancel),
          ),
          CupertinoDialogAction(
            isDestructiveAction: true,
            onPressed: () => _answer(context, true),
            child: Text(destructive),
          ),
        ],
      ),
    ),
  ),
);

/// Pops once: a second tap in the same frame would close the screen under it.
void _answer(BuildContext context, bool value) {
  final route = ModalRoute.of(context);
  if (route == null || !route.isCurrent) return;
  Navigator.of(context).pop(value);
}

/// System red stays on the destructive button, where Apple's apps use it;
/// every other button is primary text, never system blue.
class _Tinted extends StatelessWidget {
  const new({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) => CupertinoTheme(
    data: CupertinoTheme.of(context)
        .copyWith(primaryColor: SettloColors.of(context).textPrimary),
    child: child,
  );
}

/// [showCupertinoModalPopup]'s route, which under Reduce Motion appears in
/// place instead of sliding up; only the barrier fades.
class _Popup<T> extends CupertinoModalPopupRoute<T> {
  new({
    required super.builder,
    required super.barrierColor,
    required this.reduced,
  });

  final bool reduced;

  @override
  Widget buildTransitions(
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
    Widget child,
  ) => reduced
      ? Align(alignment: Alignment.bottomCenter, child: child)
      : super.buildTransitions(context, animation, secondaryAnimation, child);
}
