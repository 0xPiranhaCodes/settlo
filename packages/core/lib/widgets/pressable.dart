import 'package:flutter/material.dart';
import 'package:settlo_core/theme/colors.dart';
import 'package:settlo_core/theme/tokens.dart';

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
    this.ringRadius = const BorderRadius.all(
      Radius.circular(SettloRadius.button),
    ),
    this.label,
    this.selected,
    super.key,
  });

  /// Called on tap and keyboard activation.
  final VoidCallback? onTap;

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
        widget.onTap?.call();
        return null;
      },
    ),
  };

  @override
  Widget build(BuildContext context) {
    final c = SettloColors.of(context);
    return FocusableActionDetector(
      enabled: widget.onTap != null,
      actions: _actions,
      mouseCursor: widget.onTap == null
          ? SystemMouseCursors.basic
          : SystemMouseCursors.click,
      onShowFocusHighlight: (value) => setState(() => _highlight = value),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: widget.onTap,
        child: Semantics(
          button: true,
          enabled: widget.onTap == null ? false : null,
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
            child: ConstrainedBox(
              constraints: const BoxConstraints(
                minWidth: SettloSpacing.minTouchTarget,
                minHeight: SettloSpacing.minTouchTarget,
              ),
              child: SPressFeedback(
                enabled: widget.onTap != null,
                child: widget.child,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Shared visual response for controls that already own activation semantics.
/// Pointer observation never invokes the action or competes for gestures.
class SPressFeedback extends StatefulWidget {
  /// Wraps a Material control or the contents of an [SPressable].
  const new({
    required this.child,
    this.enabled = true,
    this.pressed,
    super.key,
  });

  /// Existing control, including its focus and activation behavior.
  final Widget child;

  /// Pressed state supplied by an existing Material control.
  final bool? pressed;

  /// Disabled controls remain still.
  final bool enabled;

  @override
  State<SPressFeedback> createState() => _SPressFeedbackState();
}

class _SPressFeedbackState extends State<SPressFeedback> {
  bool _pressed = false;

  void _setPressed(bool value) {
    if (_pressed != value) setState(() => _pressed = value);
  }

  @override
  Widget build(BuildContext context) {
    final reduceMotion = MediaQuery.disableAnimationsOf(context);
    final pressed =
        widget.enabled && (widget.pressed ?? _pressed) && !reduceMotion;
    return Listener(
      behavior: HitTestBehavior.opaque,
      onPointerDown: (_) => _setPressed(true),
      onPointerUp: (_) => _setPressed(false),
      onPointerCancel: (_) => _setPressed(false),
      child: AnimatedScale(
        scale: pressed ? SettloMotion.pressedScale : 1,
        duration: reduceMotion ? Duration.zero : SettloMotion.press,
        curve: SettloMotion.curve,
        child: widget.child,
      ),
    );
  }
}
