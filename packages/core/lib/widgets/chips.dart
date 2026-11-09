import 'package:flutter/material.dart';
import 'package:settlo_core/theme/colors.dart';
import 'package:settlo_core/theme/tokens.dart';
import 'package:settlo_core/theme/typography.dart';

/// Height of a chip or segmented control as drawn; the tap target around
/// it is [SettloSpacing.minTouchTarget].
const double _visualHeight = 36;

/// A pill filter or category chip. Selected is inverted (primary text
/// fill), never the action colour: choosing a filter is not a primary
/// action.
class SChip extends StatelessWidget {
  /// A chip labelled [label].
  const new({
    required this.label,
    required this.selected,
    required this.onSelected,
    super.key,
  });

  /// Chip text.
  final String label;

  /// Whether the chip is on.
  final bool selected;

  /// Called on tap with the opposite of [selected].
  final ValueChanged<bool> onSelected;

  @override
  Widget build(BuildContext context) {
    final c = SettloColors.of(context);
    return Semantics(
      button: true,
      selected: selected,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () => onSelected(!selected),
        child: ConstrainedBox(
          constraints: const BoxConstraints(
            minHeight: SettloSpacing.minTouchTarget,
            minWidth: SettloSpacing.minTouchTarget,
          ),
          child: Center(
            widthFactor: 1,
            heightFactor: 1,
            child: Container(
              height: _visualHeight,
              padding: const EdgeInsets.symmetric(horizontal: 14),
              decoration: ShapeDecoration(
                color: selected ? c.textPrimary : null,
                shape: StadiumBorder(
                  side: selected
                      ? BorderSide.none
                      : BorderSide(color: c.buttonBorder),
                ),
              ),
              child: Center(
                widthFactor: 1,
                child: Text(
                  label,
                  style: SettloTypography.figtree(
                    13,
                    weight: selected ? FontWeight.w500 : FontWeight.w400,
                    color: selected ? c.background : c.textPrimary,
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// One option in an [SSegmentedControl].
typedef SSegment<T> = ({T value, String label});

/// A compact segmented control (Equally / Exact / % / Shares). The selected
/// segment is lifted to the highest surface; nothing is gold.
class SSegmentedControl<T> extends StatelessWidget {
  /// A control over [segments] with [selected] chosen.
  const new({
    required this.segments,
    required this.selected,
    required this.onChanged,
    super.key,
  });

  /// The options, in order.
  final List<SSegment<T>> segments;

  /// The chosen value.
  final T selected;

  /// Called with the tapped segment's value.
  final ValueChanged<T> onChanged;

  @override
  Widget build(BuildContext context) {
    final c = SettloColors.of(context);
    const inset = (SettloSpacing.minTouchTarget - _visualHeight) / 2;
    // The track is drawn 36 high; each segment's tap target fills the full
    // 44pt band around it.
    return Stack(
      children: [
        Positioned(
          left: 0,
          right: 0,
          top: inset,
          bottom: inset,
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: c.surfaceRaised,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: c.hairline),
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 3),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              for (final segment in segments)
                _Segment(
                  label: segment.label,
                  selected: segment.value == selected,
                  onTap: () => onChanged(segment.value),
                ),
            ],
          ),
        ),
      ],
    );
  }
}

class _Segment extends StatelessWidget {
  const new({required this.label, required this.selected, required this.onTap});

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = SettloColors.of(context);
    return Semantics(
      button: true,
      selected: selected,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: SizedBox(
          height: SettloSpacing.minTouchTarget,
          child: Center(
            widthFactor: 1,
            child: Container(
              height: _visualHeight - 4,
              constraints: const BoxConstraints(minWidth: 40),
              padding: const EdgeInsets.symmetric(horizontal: 12),
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: selected ? c.surfaceHighest : null,
                borderRadius: BorderRadius.circular(10),
              ),
              child: Text(
                label,
                style: SettloTypography.figtree(
                  13,
                  weight: selected ? FontWeight.w500 : FontWeight.w400,
                  color: selected ? c.textPrimary : c.textSecondary,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
