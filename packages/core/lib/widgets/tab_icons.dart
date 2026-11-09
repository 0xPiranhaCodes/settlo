import 'package:flutter/widgets.dart';

/// The four tab bar glyphs from the canvas: 1.6px line icons on a 24-unit
/// grid, drawn in the ambient [IconTheme] colour and size.
enum STabIcon {
  /// A house.
  home,

  /// Two people.
  spaces,

  /// A banknote.
  loans,

  /// A pulse line.
  activity;

  /// This glyph as a widget.
  Widget get widget => _TabIcon(this);
}

class _TabIcon extends StatelessWidget {
  const new(this.icon);

  final STabIcon icon;

  @override
  Widget build(BuildContext context) {
    final theme = IconTheme.of(context);
    final size = theme.size ?? 24;
    return CustomPaint(
      size: Size.square(size),
      painter: _TabIconPainter(icon, theme.color ?? const Color(0xFF000000)),
    );
  }
}

class _TabIconPainter extends CustomPainter {
  const new(this.icon, this.color);

  final STabIcon icon;
  final Color color;

  // Paths transcribed from the canvas SVGs (viewBox 0 0 24 24).
  Path get _path => switch (icon) {
    STabIcon.home =>
      Path()
        ..moveTo(3, 11)
        ..lineTo(12, 4)
        ..lineTo(21, 11)
        ..lineTo(21, 20)
        ..arcToPoint(const Offset(20, 21), radius: const Radius.circular(1))
        ..lineTo(15, 21)
        ..lineTo(15, 15)
        ..lineTo(9, 15)
        ..lineTo(9, 21)
        ..lineTo(4, 21)
        ..arcToPoint(const Offset(3, 20), radius: const Radius.circular(1))
        ..close(),
    STabIcon.spaces =>
      Path()
        ..addOval(Rect.fromCircle(center: const Offset(9, 8), radius: 3.5))
        ..moveTo(2.5, 20)
        ..arcToPoint(const Offset(15.5, 20), radius: const Radius.circular(6.5))
        ..addOval(Rect.fromCircle(center: const Offset(17, 9), radius: 2.5))
        ..moveTo(16, 15.5)
        ..arcToPoint(const Offset(21.5, 20), radius: const Radius.circular(5)),
    STabIcon.loans =>
      Path()
        ..addRRect(RRect.fromLTRBR(2.5, 6, 21.5, 18, const Radius.circular(2)))
        ..addOval(Rect.fromCircle(center: const Offset(12, 12), radius: 2.5))
        ..moveTo(6, 12)
        ..lineTo(6.01, 12)
        ..moveTo(18, 12)
        ..lineTo(18.01, 12),
    STabIcon.activity =>
      Path()
        ..moveTo(3, 12)
        ..lineTo(7, 12)
        ..lineTo(10, 4)
        ..lineTo(14, 20)
        ..lineTo(17, 12)
        ..lineTo(21, 12),
  };

  @override
  void paint(Canvas canvas, Size size) {
    canvas
      ..scale(size.width / 24, size.height / 24)
      ..drawPath(
        _path,
        Paint()
          ..color = color
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.6
          ..strokeCap = StrokeCap.round
          ..strokeJoin = StrokeJoin.round,
      );
  }

  @override
  bool shouldRepaint(_TabIconPainter old) =>
      old.icon != icon || old.color != color;
}
