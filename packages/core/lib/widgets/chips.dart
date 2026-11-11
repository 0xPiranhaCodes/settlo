import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:settlo_core/theme/colors.dart';
import 'package:settlo_core/theme/tokens.dart';
import 'package:settlo_core/theme/typography.dart';
import 'package:settlo_core/widgets/controls.dart';
import 'package:settlo_core/widgets/pressable.dart';

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
    return SPressable(
      onTap: () => onSelected(!selected),
      selected: selected,
      ringRadius: BorderRadius.circular(SettloRadius.pill),
      child: ConstrainedBox(
        constraints: const BoxConstraints(
          minHeight: SettloSpacing.minTouchTarget,
          minWidth: SettloSpacing.minTouchTarget,
        ),
        child: Center(
          widthFactor: 1,
          heightFactor: 1,
          child: Container(
            constraints: const BoxConstraints(minHeight: _visualHeight),
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
              heightFactor: 1,
              child: Text(
                label,
                style: SettloTypography.subheadline(
                  weight: selected ? FontWeight.w500 : FontWeight.w400,
                  color: selected ? c.background : c.textPrimary,
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
/// segment is lifted to the highest surface; nothing is gold. On iOS it is a
/// [CupertinoSlidingSegmentedControl] across the full width.
class SSegmentedControl<T extends Object> extends StatelessWidget {
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
    if (Theme.of(context).platform == TargetPlatform.iOS) {
      return SettloCupertinoTheme(
        child: SizedBox(
          width: double.infinity,
          child: CupertinoSlidingSegmentedControl<T>(
            groupValue: selected,
            backgroundColor: c.surfaceRaised,
            thumbColor: c.surfaceHighest,
            onValueChanged: (v) {
              if (v != null) onChanged(v);
            },
            children: {
              for (final s in segments)
                // 40 inside the 2pt track inset: a 44pt target.
                s.value: ConstrainedBox(
                  constraints: const BoxConstraints(minHeight: 40),
                  child: Center(
                    child: Text(
                      s.label,
                      maxLines: 1,
                      style: SettloTypography.subheadline(
                        weight: s.value == selected
                            ? FontWeight.w500
                            : FontWeight.w400,
                        color: s.value == selected
                            ? c.textPrimary
                            : c.textSecondary,
                      ),
                    ),
                  ),
                ),
            },
          ),
        ),
      );
    }
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
          child: SizedBox(
            height: (MediaQuery.textScalerOf(context).scale(15) * 1.2 + 24)
                .clamp(44, double.infinity),
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
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
    return SPressable(
      onTap: onTap,
      selected: selected,
      ringRadius: BorderRadius.circular(12),
      child: ConstrainedBox(
        constraints: const BoxConstraints(
          minHeight: SettloSpacing.minTouchTarget,
        ),
        child: Center(
          widthFactor: 1,
          child: Container(
            constraints: const BoxConstraints(
              minWidth: SettloSpacing.minTouchTarget,
              minHeight: _visualHeight - 4,
            ),
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            decoration: BoxDecoration(
              color: selected ? c.surfaceHighest : null,
              borderRadius: BorderRadius.circular(10),
            ),
            child: Text(
              label,
              style: SettloTypography.subheadline(
                weight: selected ? FontWeight.w500 : FontWeight.w400,
                color: selected ? c.textPrimary : c.textSecondary,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
