import 'package:flutter/material.dart';
import 'package:settlo_core/theme/colors.dart';

/// The owner-supplied Settlo S-mark.
///
/// It is gold on the dark theme and ink on the light theme. Although dark
/// gold shares the primary-action token, this mark is brand, not a control.
class SettloMark extends StatelessWidget {
  /// Creates a Settlo mark with an optional screen-reader [semanticsLabel].
  ///
  /// Set [semanticsLabel] to null when a parent lockup supplies the name.
  const new({this.size = 26, this.semanticsLabel = 'Settlo', super.key});

  /// The square box containing the mark.
  final double size;

  /// The name announced for the mark, or null to leave it decorative.
  final String? semanticsLabel;

  @override
  Widget build(BuildContext context) {
    final colors = SettloColors.of(context);
    final color = Theme.of(context).brightness == Brightness.dark
        ? colors.action
        : colors.textPrimary;
    final image = Image.asset(
      'assets/brand/settlo_mark.png',
      package: 'settlo_core',
      width: size,
      height: size,
      fit: BoxFit.contain,
      color: color,
      colorBlendMode: BlendMode.srcIn,
      filterQuality: FilterQuality.high,
      excludeFromSemantics: true,
    );
    final label = semanticsLabel;
    if (label == null) return image;
    return Semantics(
      image: true,
      label: label,
      excludeSemantics: true,
      child: image,
    );
  }
}
