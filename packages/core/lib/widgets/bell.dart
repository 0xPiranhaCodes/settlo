import 'package:flutter/material.dart';
import 'package:settlo_core/theme/colors.dart';
import 'package:settlo_core/theme/tokens.dart';
import 'package:settlo_core/theme/typography.dart';
import 'package:settlo_core/widgets/glass_action.dart';

/// The notifications bell of the Home and Activity artboards: a round
/// button, with how many activity entries are [unread] on it when any are.
/// The count is inverted like a selected chip, never gold: it is not an
/// action.
class SBell extends StatelessWidget {
  /// A bell showing [unread] that calls [onPressed].
  const new({required this.unread, required this.onPressed, super.key});

  /// How many entries are new; zero draws no count.
  final int unread;

  /// Called on tap.
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final c = SettloColors.of(context);
    final count = unread > 99 ? '99+' : '$unread';
    return GlassAction(
      label: unread > 0 ? 'Notifications, $count new' : 'Notifications',
      symbol: 'bell',
      badge: unread > 0 ? count : null,
      onPressed: onPressed,
      fallback: _fallback(c, count),
    );
  }

  Widget _fallback(SettloColors c, String count) => Stack(
    clipBehavior: Clip.none,
    children: [
      IconButton(
        tooltip: unread > 0 ? 'Notifications, $count new' : 'Notifications',
        onPressed: onPressed,
        style: IconButton.styleFrom(
          fixedSize: const Size.square(SettloSpacing.minTouchTarget),
          minimumSize: Size.zero,
          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
          backgroundColor: c.surface,
          side: BorderSide(color: c.hairline),
        ),
        icon: CustomPaint(
          size: const Size.square(22),
          painter: _BellPainter(c.textPrimary),
        ),
      ),
      if (unread > 0)
        Positioned(
          top: -2,
          right: -4,
          // The button's label already says the count.
          child: IgnorePointer(
            child: ExcludeSemantics(
              child: Container(
                constraints: const BoxConstraints(minWidth: 18),
                height: 24,
                padding: const EdgeInsets.symmetric(horizontal: 5),
                alignment: Alignment.center,
                decoration: ShapeDecoration(
                  color: c.textPrimary,
                  shape: const StadiumBorder(),
                ),
                child: Text(
                  count,
                  style: SettloTypography.caption1(
                    weight: FontWeight.w500,
                    color: c.background,
                  ),
                ),
              ),
            ),
          ),
        ),
    ],
  );
}

class _BellPainter extends CustomPainter {
  const new(this.color);

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.scale(size.width / 24);
    // Transcribed from the canvas SVG (viewBox 0 0 24 24).
    final path = Path()
      ..moveTo(6, 8)
      ..arcToPoint(const Offset(18, 8), radius: const Radius.circular(6))
      ..cubicTo(18, 15, 21, 17, 21, 17)
      ..lineTo(3, 17)
      ..cubicTo(3, 17, 6, 15, 6, 8)
      ..moveTo(10.3, 21)
      ..arcToPoint(
        const Offset(13.7, 21),
        radius: const Radius.circular(1.94),
        clockwise: false,
      );
    canvas.drawPath(
      path,
      Paint()
        ..color = color
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.6
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round,
    );
  }

  @override
  bool shouldRepaint(_BellPainter old) => old.color != color;
}
