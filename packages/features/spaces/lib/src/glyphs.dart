import 'package:flutter/widgets.dart';
import 'package:settlo_core/settlo_core.dart';

/// The line glyphs the Spaces artboards use, on a 24-unit grid. House and
/// two people come from `STabIcon`.
enum SpacesGlyph {
  /// New space, add expense.
  plus,

  /// A paper plane: trips.
  plane,

  /// Close a sheet; remove a person.
  close,

  /// Back.
  back,

  /// A row that opens something.
  chevron,

  /// A recurring expense.
  clock,

  /// A card: the UPI ID.
  card,
}

/// [glyph] at [size] in [color], stroked [stroke] units wide on the 24 grid.
class SpacesIcon extends StatelessWidget {
  /// An icon drawing [glyph].
  const new(
    this.glyph, {
    required this.color,
    this.size = 20,
    this.stroke = 1.6,
    super.key,
  });

  /// What to draw.
  final SpacesGlyph glyph;

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

/// The icon for a space of [kind] in a 44px tile (SpacesList).
class SpaceKindTile extends StatelessWidget {
  /// A tile for [kind].
  const new(this.kind, {super.key});

  /// What the space is for.
  final SpaceKind kind;

  @override
  Widget build(BuildContext context) {
    final c = SettloColors.of(context);
    return Container(
      width: 44,
      height: 44,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: c.surfaceRaised,
        borderRadius: BorderRadius.circular(16),
      ),
      child: IconTheme(
        data: IconThemeData(color: c.textPrimary, size: 20),
        child: switch (kind) {
          SpaceKind.flat => STabIcon.home.widget,
          SpaceKind.trip => SpacesIcon(SpacesGlyph.plane, color: c.textPrimary),
          SpaceKind.friend || SpaceKind.other => STabIcon.spaces.widget,
        },
      ),
    );
  }
}

class _GlyphPainter extends CustomPainter {
  const new(this.glyph, this.color, this.stroke);

  final SpacesGlyph glyph;
  final Color color;
  final double stroke;

  // Paths transcribed from the canvas SVGs (viewBox 0 0 24 24).
  Path get _path => switch (glyph) {
    SpacesGlyph.plus =>
      Path()
        ..moveTo(12, 5)
        ..lineTo(12, 19)
        ..moveTo(5, 12)
        ..lineTo(19, 12),
    SpacesGlyph.plane =>
      Path()
        ..moveTo(3, 12)
        ..lineTo(21, 4)
        ..lineTo(17, 20)
        ..lineTo(12, 14)
        ..close()
        ..moveTo(12, 14)
        ..lineTo(17, 4),
    SpacesGlyph.close =>
      Path()
        ..moveTo(6, 6)
        ..lineTo(18, 18)
        ..moveTo(18, 6)
        ..lineTo(6, 18),
    SpacesGlyph.back =>
      Path()
        ..moveTo(15, 5)
        ..lineTo(8, 12)
        ..lineTo(15, 19),
    SpacesGlyph.chevron =>
      Path()
        ..moveTo(9, 6)
        ..lineTo(15, 12)
        ..lineTo(9, 18),
    SpacesGlyph.clock =>
      Path()
        ..moveTo(12, 8)
        ..lineTo(12, 12)
        ..lineTo(14.5, 14.5)
        ..addOval(Rect.fromCircle(center: const Offset(12, 12), radius: 8.5)),
    SpacesGlyph.card =>
      Path()
        ..addRect(const Rect.fromLTRB(4, 7, 20, 17))
        ..moveTo(4, 11)
        ..lineTo(20, 11),
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
