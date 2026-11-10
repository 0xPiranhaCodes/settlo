import 'package:flutter/widgets.dart';

/// The owner-approved warm arcs shared by Welcome and Home.
///
/// The painter owns the background fill as well as the two hairline arcs so
/// both screens render the same glow rather than maintaining lookalikes.
class WelcomeBackgroundPainter extends CustomPainter {
  /// Creates the shared background treatment.
  const new({
    required this.background,
    required this.gold,
    required this.highlight,
  });

  /// The solid screen background.
  final Color background;

  /// The base gold used by the arcs.
  final Color gold;

  /// The hottest point in each arc.
  final Color highlight;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawRect(Offset.zero & size, Paint()..color = background);
    final topArc = Path()
      ..moveTo(size.width * 0.37, -4)
      ..quadraticBezierTo(
        size.width * 0.82,
        size.height * 0.065,
        size.width + 12,
        size.height * 0.32,
      );
    final bottomArc = Path()
      ..moveTo(-8, size.height * 0.95)
      ..quadraticBezierTo(
        size.width * 0.2,
        size.height * 0.97,
        size.width * 0.48,
        size.height + 8,
      );
    final bounds = Offset.zero & size;
    final hot = Color.lerp(gold, highlight, 0.96)!;
    final topShader = LinearGradient(
      colors: [
        gold.withValues(alpha: 0.18),
        gold.withValues(alpha: 0.35),
        gold,
        hot,
        gold,
        gold.withValues(alpha: 0.36),
        gold.withValues(alpha: 0),
      ],
      stops: const [0, 0.5, 0.6, 0.66, 0.72, 0.82, 0.95],
    ).createShader(bounds);
    final topHotShader = LinearGradient(
      colors: [hot.withValues(alpha: 0), hot, hot.withValues(alpha: 0)],
      stops: const [0.61, 0.66, 0.71],
    ).createShader(bounds);
    final bottomShader = LinearGradient(
      colors: [
        gold.withValues(alpha: 0.3),
        gold,
        hot,
        gold,
        gold.withValues(alpha: 0.25),
        gold.withValues(alpha: 0),
      ],
      stops: const [0, 0.045, 0.075, 0.105, 0.2, 0.245],
    ).createShader(bounds);
    final bottomHotShader = LinearGradient(
      colors: [hot.withValues(alpha: 0), hot, hot.withValues(alpha: 0)],
      stops: const [0.045, 0.075, 0.105],
    ).createShader(bounds);

    void drawGlowingArc(Path path, Shader shader, Shader hotShader) {
      canvas
        ..drawPath(
          path,
          Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = 2.5
            ..strokeCap = StrokeCap.round
            ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 1.8)
            ..colorFilter = const ColorFilter.mode(
              Color(0x3DFFFFFF),
              BlendMode.modulate,
            )
            ..shader = shader,
        )
        ..drawPath(
          path,
          Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = 5.5
            ..strokeCap = StrokeCap.round
            ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 3.2)
            ..colorFilter = const ColorFilter.mode(
              Color(0xCCFFFFFF),
              BlendMode.modulate,
            )
            ..shader = hotShader,
        )
        ..drawPath(
          path,
          Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = 1
            ..strokeCap = StrokeCap.round
            ..shader = shader,
        )
        ..drawPath(
          path,
          Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = 2
            ..strokeCap = StrokeCap.round
            ..shader = hotShader,
        );
    }

    drawGlowingArc(topArc, topShader, topHotShader);
    drawGlowingArc(bottomArc, bottomShader, bottomHotShader);
  }

  @override
  bool shouldRepaint(WelcomeBackgroundPainter oldDelegate) =>
      oldDelegate.background != background ||
      oldDelegate.gold != gold ||
      oldDelegate.highlight != highlight;
}
