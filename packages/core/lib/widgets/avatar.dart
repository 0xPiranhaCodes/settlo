import 'package:flutter/widgets.dart';
import 'package:settlo_core/theme/colors.dart';
import 'package:settlo_core/theme/typography.dart';

/// A round avatar showing the first letter of [name] on the highest
/// surface. Avatars are never gold: a person is not an action.
class SAvatar extends StatelessWidget {
  /// An avatar for [name], [size] across (40 in lists, 36 in activity).
  const new(this.name, {this.size = 40, super.key});

  /// The person's display name.
  final String name;

  /// Diameter.
  final double size;

  @override
  Widget build(BuildContext context) {
    final c = SettloColors.of(context);
    final trimmed = name.trim();
    final initial = trimmed.isEmpty
        ? '?'
        : String.fromCharCodes(trimmed.runes.take(1)).toUpperCase();
    return Semantics(
      label: name,
      excludeSemantics: true,
      child: Container(
        width: size,
        height: size,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: c.surfaceHighest,
          shape: BoxShape.circle,
        ),
        child: Text(
          initial,
          style: SettloTypography.figtree(
            size * 0.375,
            weight: FontWeight.w500,
            color: c.textPrimary,
          ).copyWith(height: 1),
        ),
      ),
    );
  }
}
