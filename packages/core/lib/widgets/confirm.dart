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
}) => showCupertinoModalPopup<bool>(
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

/// Asks with a native [CupertinoAlertDialog], for an irreversible choice
/// such as deleting the account. True when [destructive] is chosen, false
/// for [cancel]. iOS only.
Future<bool?> showSettloAlert({
  required BuildContext context,
  required String title,
  required String message,
  required String destructive,
  required String cancel,
}) => showCupertinoDialog<bool>(
  context: context,
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
