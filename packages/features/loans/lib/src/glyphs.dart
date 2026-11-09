import 'dart:math' as math;

import 'package:flutter/widgets.dart';

/// A canvas line icon in a 24 box, drawn as round-capped strokes.
class LoanGlyph extends StatelessWidget {
  /// [lines] in [color] at [size], [stroke] wide in the 24 box.
  const new(
    this.lines, {
    required this.color,
    this.size = 22,
    this.stroke = 1.6,
    super.key,
  });

  /// Back (`M15 5l-7 7 7 7`).
  static const back = [
    [Offset(15, 5), Offset(8, 12), Offset(15, 19)],
  ];

  /// Chevron down (`M6 9l6 6 6-6`).
  static const chevronDown = [
    [Offset(6, 9), Offset(12, 15), Offset(18, 9)],
  ];

  /// Plus (`M12 5v14M5 12h14`).
  static const plus = [
    [Offset(12, 5), Offset(12, 19)],
    [Offset(5, 12), Offset(19, 12)],
  ];

  /// Arrow right (`M5 12h14m0 0l-5-5m5 5l-5 5`).
  static const arrow = [
    [Offset(5, 12), Offset(19, 12)],
    [Offset(14, 7), Offset(19, 12), Offset(14, 17)],
  ];

  /// Person (`circle 12 9 r3.5`, `M5 20a7 7 0 0 1 14 0`).
  static final List<List<Offset>> person = [
    _arc(const Offset(12, 9), 3.5, 0, 2 * math.pi),
    _arc(const Offset(12, 20), 7, math.pi, 2 * math.pi),
  ];

  static List<Offset> _arc(Offset c, double r, double from, double to) => [
    for (var i = 0; i <= 24; i++)
      c + Offset.fromDirection(from + (to - from) * i / 24, r),
  ];

  /// Check (`M5 12l5 5L20 7`).
  static const check = [
    [Offset(5, 12), Offset(10, 17), Offset(20, 7)],
  ];

  /// Shield with a check, used for final repayment decisions.
  static const shieldCheck = [
    [
      Offset(12, 3),
      Offset(20, 6),
      Offset(20, 12),
      Offset(18, 17),
      Offset(12, 21),
      Offset(6, 17),
      Offset(4, 12),
      Offset(4, 6),
      Offset(12, 3),
    ],
    [Offset(9, 12), Offset(11, 14), Offset(15, 10)],
  ];

  /// Polylines in the 24 box.
  final List<List<Offset>> lines;

  /// Stroke colour.
  final Color color;

  /// Drawn size.
  final double size;

  /// Stroke width in the 24 box.
  final double stroke;

  @override
  Widget build(BuildContext context) => ExcludeSemantics(
    child: CustomPaint(
      size: Size.square(size),
      painter: _Lines(lines, color, stroke),
    ),
  );
}

class _Lines extends CustomPainter {
  const new(this.lines, this.color, this.stroke);

  final List<List<Offset>> lines;
  final Color color;
  final double stroke;

  @override
  void paint(Canvas canvas, Size size) {
    final s = size.width / 24;
    final paint = Paint()
      ..color = color
      ..strokeWidth = stroke * s
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..style = PaintingStyle.stroke;
    for (final line in lines) {
      canvas.drawPath(
        Path()..addPolygon([for (final p in line) p * s], false),
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(_Lines old) =>
      old.lines != lines || old.color != color || old.stroke != stroke;
}
