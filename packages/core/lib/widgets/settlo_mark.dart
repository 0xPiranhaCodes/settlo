import 'package:flutter/material.dart';
import 'package:settlo_core/theme/colors.dart';

/// The owner-supplied Settlo S-mark.
///
/// In the app the mark is monochrome: ink on the light theme and white on the
/// dark theme. The gold mark is for marketing only (site, social card, store).
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
    final color = SettloColors.of(context).textPrimary;
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
      errorBuilder: (context, error, stackTrace) => SizedBox.square(
        dimension: size,
        child: FittedBox(
          child: Text(
            'S',
            style: TextStyle(color: color, fontWeight: FontWeight.w800),
          ),
        ),
      ),
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
