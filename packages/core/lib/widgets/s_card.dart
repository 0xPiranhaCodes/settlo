import 'package:flutter/material.dart';
import 'package:settlo_core/theme/colors.dart';
import 'package:settlo_core/theme/tokens.dart';

/// A Settlo card: surface fill, 1px hairline edge and a 1px specular
/// highlight along the inside of the top edge and soft ambient depth.
///
/// Canvas: `border: 1px solid hairline; box-shadow: inset 0 1px 0 specular`.
class SCard extends StatelessWidget {
  /// A card around [child]. [hero] uses the larger radius for the one
  /// headline card on a screen.
  const new({required this.child, this.padding, this.hero = false, super.key});

  /// The card's content.
  final Widget child;

  /// Space between the edge and [child].
  final EdgeInsetsGeometry? padding;

  /// Whether this is the screen's hero card (radius 28 rather than 24).
  final bool hero;

  @override
  Widget build(BuildContext context) {
    final c = SettloColors.of(context);
    final radius = hero ? SettloRadius.cardHero : SettloRadius.card;
    const edge = SettloElevation.hairline;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: c.surface,
        borderRadius: BorderRadius.circular(radius),
        border: Border.all(
          color: SettloElevation.border(
            dark: Theme.of(context).brightness == Brightness.dark,
          ),
        ),
        boxShadow: SettloElevation.ambient(
          dark: Theme.of(context).brightness == Brightness.dark,
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.all(edge),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(radius - edge),
          child: Stack(
            children: [
              Padding(
                padding:
                    padding ??
                    EdgeInsets.all(
                      hero ? SettloSpacing.x3 : SettloSpacing.screenMargin,
                    ),
                child: child,
              ),
              Positioned(
                top: 0,
                left: 0,
                right: 0,
                height: edge,
                child: ColoredBox(color: c.specular),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
