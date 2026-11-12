import 'dart:math' as math;

import 'package:flutter/widgets.dart';
import 'package:settlo_core/settlo_core.dart';

/// A loan's progress ring (canvas note n20: a loan has a clear end, so a
/// ring, not a bar). The arc is primary text on the highest surface,
/// never gold, and starts at twelve o'clock.
class LoanRing extends StatelessWidget {
  /// A ring [progress] (0–1) of the way round, from confirmed repayments.
  const new(this.progress, {this.size = 112, super.key});

  /// The share repaid.
  final double progress;

  /// Diameter.
  final double size;

  /// The percentage shown: rounded down, so 100% means fully repaid.
  int get percent => (progress.clamp(0, 1) * 100).floor();

  @override
  Widget build(BuildContext context) {
    final c = SettloColors.of(context);
    return Semantics(
      label: '$percent percent repaid',
      excludeSemantics: true,
      child: SizedBox.square(
        dimension: size,
        child: CustomPaint(
          painter: LoanRingPainter(
            progress,
            track: c.surfaceHighest,
            arc: c.brandAccent,
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(
                '$percent%',
                style: SettloTypography.amount(20, color: c.textPrimary),
              ),
              Text(
                'repaid',
                style: SettloTypography.caption1(color: c.textSecondary),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Paints [LoanRing]: a [stroke]-wide track and a round-capped arc.
class LoanRingPainter extends CustomPainter {
  /// The ring for [progress] in [arc] over [track].
  const new(
    this.progress, {
    required this.track,
    required this.arc,
    this.stroke = 10,
  });

  /// The share repaid, clamped to 0–1.
  final double progress;

  /// The full circle under the arc.
  final Color track;

  /// The repaid arc.
  final Color arc;

  /// Stroke width; the canvas ring is r 51 in a 112 box, stroke 10.
  final double stroke;

  /// Where the arc goes in [size]: the circle's bounds, the start angle
  /// (twelve o'clock) and the clockwise sweep, all in radians.
  ({Rect rect, double start, double sweep}) geometry(Size size) => (
    rect: Rect.fromCircle(
      center: size.center(Offset.zero),
      radius: (size.shortestSide - stroke) / 2,
    ),
    start: -math.pi / 2,
    sweep: 2 * math.pi * progress.clamp(0, 1),
  );

  @override
  void paint(Canvas canvas, Size size) {
    final (:rect, :start, :sweep) = geometry(size);
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = stroke;
    canvas.drawCircle(rect.center, rect.width / 2, paint..color = track);
    // A round cap on an empty arc would draw a dot: nothing is repaid.
    if (sweep == 0) return;
    canvas.drawArc(
      rect,
      start,
      sweep,
      false,
      paint
        ..color = arc
        ..strokeCap = StrokeCap.round,
    );
  }

  @override
  bool shouldRepaint(LoanRingPainter old) =>
      old.progress != progress ||
      old.track != track ||
      old.arc != arc ||
      old.stroke != stroke;
}
