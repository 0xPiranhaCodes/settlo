import 'package:flutter/material.dart';
import 'package:settlo_core/theme/colors.dart';
import 'package:settlo_core/theme/tokens.dart';
import 'package:settlo_core/widgets/pressable.dart';

/// The shared grabber and title row for task sheets.
class SSheetHeader extends StatelessWidget {
  /// Use the compact row once an amount sheet collapses.
  const new({
    required this.title,
    required this.onClose,
    this.compact = false,
    this.showGrabber = true,
    super.key,
  });

  /// Sheet title.
  final String title;

  /// Close action.
  final VoidCallback onClose;

  /// Omits the grabber for a collapsed navigation bar.
  final bool compact;

  /// Android routes supply their own draggable handle.
  final bool showGrabber;

  /// Expanded navigation area, matching the amount sheet's 108 minus 24.
  static const double extent = 84;

  /// Inset contributed by the amount sheet frame, also used by Profile.
  static const double frameInset = 1;
  @override
  Widget build(BuildContext context) {
    final c = SettloColors.of(context);
    if (compact || !showGrabber) return _row(context);
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Center(
          child: Container(
            key: const ValueKey('task-sheet-grabber'),
            width: 36,
            height: 4,
            margin: const EdgeInsets.only(top: 10),
            decoration: BoxDecoration(
              color: c.surfaceHighest,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
        ),
        const SizedBox(height: 10),
        _row(context),
      ],
    );
  }

  Widget _row(BuildContext context) {
    final c = SettloColors.of(context);
    final text = Theme.of(context).textTheme;
    final largeText = MediaQuery.textScalerOf(context).scale(14) > 21;
    return Row(
      children: [
        Transform.translate(
          offset: const Offset(-12, 0),
          child: SPressable(
            onTap: onClose,
            label: 'Close',
            ringRadius: BorderRadius.circular(SettloSpacing.minTouchTarget / 2),
            child: SizedBox.square(
              dimension: SettloSpacing.minTouchTarget,
              child: Center(
                child: CustomPaint(
                  size: const Size.square(22),
                  painter: _CrossPainter(c.textPrimary),
                ),
              ),
            ),
          ),
        ),
        Expanded(
          child: Semantics(
            header: true,
            child: FittedBox(
              fit: BoxFit.scaleDown,
              child: Text(
                title,
                textAlign: TextAlign.center,
                maxLines: 1,
                overflow: largeText
                    ? TextOverflow.visible
                    : TextOverflow.ellipsis,
                style: text.titleLarge,
              ),
            ),
          ),
        ),
        const SizedBox(width: SettloSpacing.minTouchTarget - 12),
      ],
    );
  }
}

/// The canvas close icon: an X in a 24 box, stroke 1.6, round caps.
class _CrossPainter extends CustomPainter {
  const new(this.color);

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final scale = size.width / 24;
    final paint = Paint()
      ..color = color
      ..strokeWidth = 1.6 * scale
      ..strokeCap = StrokeCap.round;
    canvas
      ..drawLine(
        const Offset(6, 6) * scale,
        const Offset(18, 18) * scale,
        paint,
      )
      ..drawLine(
        const Offset(18, 6) * scale,
        const Offset(6, 18) * scale,
        paint,
      );
  }

  @override
  bool shouldRepaint(_CrossPainter old) => old.color != color;
}
