import 'package:flutter/material.dart';
import 'package:settlo_core/theme/tokens.dart';
import 'package:settlo_core/widgets/pressable.dart';

/// A primary action: marigold in dark, jade in light.
///
/// Radius 16, at least 44pt tall (50 by default, as on the canvas). An
/// optional [icon] trails the label.
class SPrimaryButton extends StatelessWidget {
  /// A primary button labelled [label]. A null [onPressed] disables it.
  const new({
    required this.label,
    required this.onPressed,
    this.icon,
    super.key,
  });

  /// Button text, in sentence case.
  final String label;

  /// Called on tap.
  final VoidCallback? onPressed;

  /// Trailing icon, coloured by the button.
  final Widget? icon;

  @override
  Widget build(BuildContext context) => SPressFeedback(
    enabled: onPressed != null,
    child: FilledButton(
      style: icon == null
          ? null
          : FilledButton.styleFrom(
              padding: const EdgeInsets.symmetric(horizontal: 12),
            ),
      onPressed: onPressed,
      child: _ButtonLabel(label: label, icon: icon),
    ),
  );
}

/// A secondary action: raised surface, 1px border, primary text.
class SSecondaryButton extends StatelessWidget {
  /// A secondary button labelled [label]. A null [onPressed] disables it.
  const new({
    required this.label,
    required this.onPressed,
    this.icon,
    super.key,
  });

  /// Button text, in sentence case.
  final String label;

  /// Called on tap.
  final VoidCallback? onPressed;

  /// Trailing icon, coloured by the button.
  final Widget? icon;

  @override
  Widget build(BuildContext context) => SPressFeedback(
    enabled: onPressed != null,
    child: OutlinedButton(
      onPressed: onPressed,
      child: _ButtonLabel(label: label, icon: icon),
    ),
  );
}

class _ButtonLabel extends StatelessWidget {
  const new({required this.label, required this.icon});

  final String label;
  final Widget? icon;

  @override
  Widget build(BuildContext context) {
    final icon = this.icon;
    final large = MediaQuery.textScalerOf(context).scale(1) >= 1.3;
    final text = Text(label, maxLines: 1, overflow: TextOverflow.ellipsis);
    final content = large
        ? FittedBox(fit: BoxFit.scaleDown, child: Text(label, maxLines: 1))
        : text;
    if (icon == null) return content;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Flexible(child: content),
        const SizedBox(width: SettloSpacing.half),
        IconTheme.merge(data: const IconThemeData(size: 18), child: icon),
      ],
    );
  }
}
