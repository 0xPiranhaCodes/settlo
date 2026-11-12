import 'package:flutter/material.dart';
import 'package:settlo_core/theme/colors.dart';

/// The mark's asset in package `settlo_core`.
const settloMarkAsset = 'assets/brand/sabkijeb_mark.png';

/// The owner-supplied SabkiJeb logo, clipped to a circle (#203).
///
/// The logo brings its own deep-forest background, so one asset reads on
/// both themes.
class SettloMark extends StatelessWidget {
  /// Creates a SabkiJeb mark with an optional screen-reader [semanticsLabel].
  ///
  /// Set [semanticsLabel] to null when a parent lockup supplies the name.
  const new({this.size = 26, this.semanticsLabel = 'SabkiJeb', super.key});

  /// The square box containing the mark.
  final double size;

  /// The name announced for the mark, or null to leave it decorative.
  final String? semanticsLabel;

  @override
  Widget build(BuildContext context) {
    final color = SettloColors.of(context).textPrimary;
    final image = Image.asset(
      settloMarkAsset,
      package: 'settlo_core',
      width: size,
      height: size,
      fit: BoxFit.contain,
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
