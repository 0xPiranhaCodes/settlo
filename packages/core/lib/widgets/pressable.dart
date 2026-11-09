import 'package:flutter/material.dart';
import 'package:settlo_core/theme/colors.dart';

/// A custom-drawn control that behaves like a button: it takes keyboard
/// focus, activates on tap and on Enter or Space, shows a focus ring in
/// primary text (never gold) while focused from the keyboard, and reports
/// itself as a button.
///
/// For Settlo components only; feature code uses the components.
class SPressable extends StatefulWidget {
  /// A control around [child] that calls [onTap].
  const new({
    required this.onTap,
    required this.child,
    required this.ringRadius,
    this.label,
    this.selected,
    super.key,
  });

  /// Called on tap and keyboard activation.
  final VoidCallback onTap;

  /// What is drawn. It sets the size of the target and of the ring.
  final Widget child;

  /// Corner radius of the focus ring.
  final BorderRadius ringRadius;

  /// Accessible label. When set, it replaces the semantics of [child].
  final String? label;

  /// Whether the control is the chosen one of a set, if it is in one.
  final bool? selected;

  @override
  State<SPressable> createState() => _SPressableState();
}

class _SPressableState extends State<SPressable> {
  bool _highlight = false;

  late final Map<Type, Action<Intent>> _actions = {
    ActivateIntent: CallbackAction<ActivateIntent>(
      onInvoke: (_) {
        widget.onTap();
        return null;
      },
    ),
  };

  @override
  Widget build(BuildContext context) {
    final c = SettloColors.of(context);
    return FocusableActionDetector(
      actions: _actions,
      mouseCursor: SystemMouseCursors.click,
      onShowFocusHighlight: (value) => setState(() => _highlight = value),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: widget.onTap,
        child: Semantics(
          button: true,
          selected: widget.selected,
          label: widget.label,
          excludeSemantics: widget.label != null,
          child: DecoratedBox(
            position: DecorationPosition.foreground,
            decoration: BoxDecoration(
              borderRadius: widget.ringRadius,
              border: _highlight
                  ? Border.all(color: c.textPrimary, width: 2)
                  : null,
            ),
            child: widget.child,
          ),
        ),
      ),
    );
  }
}
