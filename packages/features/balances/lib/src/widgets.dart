import 'package:flutter/widgets.dart';

/// The line glyphs the Home artboards use, on a 24-unit grid. House and
/// banknote come from `STabIcon`.
enum HomeGlyph {
  /// Plus on Add expense.
  plus,

  /// Arrow after Start.
  arrow,

  /// Tick on the ledger-found card.
  check,

  /// Shield with a tick beside the privacy note.
  shield,

  /// A person: contacts, and spaces with one friend.
  person,

  /// A paper plane: trips.
  plane,
}

/// [glyph] at [size] in [color], stroked [stroke] units wide on the 24 grid.
class HomeIcon extends StatelessWidget {
  /// An icon drawing [glyph].
  const new(
    this.glyph, {
    required this.color,
    this.size = 20,
    this.stroke = 1.6,
    super.key,
  });

  /// What to draw.
  final HomeGlyph glyph;

  /// Stroke colour.
  final Color color;

  /// Width and height.
  final double size;

  /// Stroke width in grid units.
  final double stroke;

  @override
  Widget build(BuildContext context) => ExcludeSemantics(
    child: CustomPaint(
      size: Size.square(size),
      painter: _GlyphPainter(glyph, color, stroke),
    ),
  );
}

class _GlyphPainter extends CustomPainter {
  const new(this.glyph, this.color, this.stroke);

  final HomeGlyph glyph;
  final Color color;
  final double stroke;

  // Paths transcribed from the canvas SVGs (viewBox 0 0 24 24).
  Path get _path => switch (glyph) {
    HomeGlyph.plus =>
      Path()
        ..moveTo(12, 5)
        ..lineTo(12, 19)
        ..moveTo(5, 12)
        ..lineTo(19, 12),
    HomeGlyph.arrow =>
      Path()
        ..moveTo(5, 12)
        ..lineTo(19, 12)
        ..lineTo(14, 7)
        ..moveTo(19, 12)
        ..lineTo(14, 17),
    HomeGlyph.check =>
      Path()
        ..moveTo(5, 12)
        ..lineTo(10, 17)
        ..lineTo(20, 7),
    HomeGlyph.shield =>
      Path()
        ..moveTo(12, 3)
        ..lineTo(20, 6)
        ..lineTo(20, 12)
        ..cubicTo(20, 17, 16.5, 20, 12, 21)
        ..cubicTo(7.5, 20, 4, 17, 4, 12)
        ..lineTo(4, 6)
        ..close()
        ..moveTo(9, 12)
        ..lineTo(11, 14)
        ..lineTo(15, 10),
    HomeGlyph.person =>
      Path()
        ..addOval(Rect.fromCircle(center: const Offset(12, 9), radius: 3.5))
        ..moveTo(5, 20)
        ..arcToPoint(const Offset(19, 20), radius: const Radius.circular(7)),
    HomeGlyph.plane =>
      Path()
        ..moveTo(3, 12)
        ..lineTo(21, 4)
        ..lineTo(17, 20)
        ..lineTo(12, 14)
        ..close()
        ..moveTo(12, 14)
        ..lineTo(17, 4),
  };

  @override
  void paint(Canvas canvas, Size size) {
    canvas
      ..save()
      ..scale(size.width / 24)
      ..drawPath(
        _path,
        Paint()
          ..color = color
          ..style = PaintingStyle.stroke
          ..strokeWidth = stroke
          ..strokeCap = StrokeCap.round
          ..strokeJoin = StrokeJoin.round,
      )
      ..restore();
  }

  @override
  bool shouldRepaint(_GlyphPainter old) =>
      old.glyph != glyph || old.color != color || old.stroke != stroke;
}
