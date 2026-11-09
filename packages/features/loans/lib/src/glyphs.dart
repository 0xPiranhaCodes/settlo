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

  /// Plus (`M12 5v14M5 12h14`).
  static const plus = [
    [Offset(12, 5), Offset(12, 19)],
    [Offset(5, 12), Offset(19, 12)],
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
