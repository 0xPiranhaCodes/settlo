import 'package:flutter/widgets.dart';

/// Line glyphs used by the Profile artboard, on its 24-unit SVG grid.
enum ProfileGlyph {
  /// Back arrow.
  back,

  /// UPI card wallet.
  wallet,

  /// Reminder bell.
  bell,

  /// Contact silhouette.
  person,

  /// App-lock shield.
  shield,

  /// Export arrow.
  download,

  /// Mobile phone.
  phone,

  /// Appearance sun.
  appearance,

  /// Profile edit pencil.
  edit,

  /// Sign-out door and arrow.
  logout,

  /// Delete-account bin.
  trash,

  /// Forward disclosure arrow.
  chevron,

  /// Selected-option tick.
  check,
}

/// A canvas-stable profile icon that does not depend on MaterialIcons.
class ProfileIcon extends StatelessWidget {
  /// Draws [glyph] at [size] in [color].
  const new(
    this.glyph, {
    required this.color,
    this.size = 20,
    this.stroke = 1.6,
    super.key,
  });

  /// Shape to draw.
  final ProfileGlyph glyph;

  /// Stroke colour.
  final Color color;

  /// Square dimensions.
  final double size;

  /// Stroke width on the 24-unit grid.
  final double stroke;

  @override
  Widget build(BuildContext context) => ExcludeSemantics(
    child: CustomPaint(
      size: Size.square(size),
      painter: _ProfileGlyphPainter(glyph, color, stroke),
    ),
  );
}

class _ProfileGlyphPainter extends CustomPainter {
  const new(this.glyph, this.color, this.stroke);

  final ProfileGlyph glyph;
  final Color color;
  final double stroke;

  Path get _path => switch (glyph) {
    ProfileGlyph.back =>
      Path()
        ..moveTo(15, 5)
        ..lineTo(8, 12)
        ..lineTo(15, 19),
    ProfileGlyph.wallet =>
      Path()
        ..addRect(const Rect.fromLTWH(4, 7, 16, 10))
        ..moveTo(4, 11)
        ..lineTo(20, 11),
    ProfileGlyph.bell =>
      Path()
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
        ),
    ProfileGlyph.person =>
      Path()
        ..addOval(Rect.fromCircle(center: const Offset(12, 9), radius: 3.5))
        ..moveTo(5, 20)
        ..arcToPoint(const Offset(19, 20), radius: const Radius.circular(7)),
    ProfileGlyph.shield =>
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
    ProfileGlyph.download =>
      Path()
        ..moveTo(12, 4)
        ..lineTo(12, 16)
        ..moveTo(8, 12)
        ..lineTo(12, 16)
        ..lineTo(16, 12)
        ..moveTo(5, 20)
        ..lineTo(19, 20),
    ProfileGlyph.phone =>
      Path()
        ..addRRect(
          RRect.fromRectAndRadius(
            const Rect.fromLTWH(7, 2.5, 10, 19),
            const Radius.circular(2),
          ),
        )
        ..moveTo(11, 18)
        ..lineTo(13, 18),
    ProfileGlyph.appearance =>
      Path()
        ..addOval(Rect.fromCircle(center: const Offset(12, 12), radius: 4))
        ..moveTo(12, 2)
        ..lineTo(12, 5)
        ..moveTo(12, 19)
        ..lineTo(12, 22)
        ..moveTo(2, 12)
        ..lineTo(5, 12)
        ..moveTo(19, 12)
        ..lineTo(22, 12)
        ..moveTo(5, 5)
        ..lineTo(7, 7)
        ..moveTo(17, 17)
        ..lineTo(19, 19)
        ..moveTo(19, 5)
        ..lineTo(17, 7)
        ..moveTo(7, 17)
        ..lineTo(5, 19),
    ProfileGlyph.edit =>
      Path()
        ..moveTo(4, 20)
        ..lineTo(8, 19)
        ..lineTo(19, 8)
        ..lineTo(16, 5)
        ..lineTo(5, 16)
        ..close()
        ..moveTo(14.5, 6.5)
        ..lineTo(17.5, 9.5),
    ProfileGlyph.logout =>
      Path()
        ..moveTo(10, 4)
        ..lineTo(5, 4)
        ..lineTo(5, 20)
        ..lineTo(10, 20)
        ..moveTo(13, 8)
        ..lineTo(17, 12)
        ..lineTo(13, 16)
        ..moveTo(8, 12)
        ..lineTo(17, 12),
    ProfileGlyph.trash =>
      Path()
        ..moveTo(4, 7)
        ..lineTo(20, 7)
        ..moveTo(9, 7)
        ..lineTo(9, 4)
        ..lineTo(15, 4)
        ..lineTo(15, 7)
        ..moveTo(6, 7)
        ..lineTo(7, 20)
        ..lineTo(17, 20)
        ..lineTo(18, 7),
    ProfileGlyph.chevron =>
      Path()
        ..moveTo(9, 6)
        ..lineTo(15, 12)
        ..lineTo(9, 18),
    ProfileGlyph.check =>
      Path()
        ..moveTo(5, 12)
        ..lineTo(10, 17)
        ..lineTo(20, 7),
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
  bool shouldRepaint(_ProfileGlyphPainter old) =>
      old.glyph != glyph || old.color != color || old.stroke != stroke;
}
