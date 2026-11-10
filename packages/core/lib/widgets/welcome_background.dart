import 'package:flutter/widgets.dart';

/// Arc geometry for the screen using the shared warm treatment.
enum SettloArcPlacement {
  /// Welcome's top-right and bottom-left framing arcs.
  welcome,

  /// Home's single bottom-right arc, kept above the floating navigation.
  home,
}

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
    this.placement = SettloArcPlacement.welcome,
  });

  /// The solid screen background.
  final Color background;

  /// The base gold used by the arcs.
  final Color gold;

  /// The hottest point in each arc.
  final Color highlight;

  /// Where the shared arc treatment is placed.
  final SettloArcPlacement placement;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawRect(Offset.zero & size, Paint()..color = background);
    final paths = switch (placement) {
      SettloArcPlacement.welcome => (
        Path()
          ..moveTo(size.width * 0.37, -4)
          ..quadraticBezierTo(
            size.width * 0.82,
            size.height * 0.065,
            size.width + 12,
            size.height * 0.32,
          ),
        Path()
          ..moveTo(-8, size.height * 0.95)
          ..quadraticBezierTo(
            size.width * 0.2,
            size.height * 0.97,
            size.width * 0.48,
            size.height + 8,
          ),
      ),
      SettloArcPlacement.home => (
        null,
        Path()
          ..moveTo(size.width * 0.52, size.height * 0.86)
          ..quadraticBezierTo(
            size.width * 0.73,
            size.height * 0.78,
            size.width + 10,
            size.height * 0.8,
          ),
      ),
    };
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
    final (bottomShader, bottomHotShader) = switch (placement) {
      SettloArcPlacement.welcome => (
        LinearGradient(
          colors: [
            gold.withValues(alpha: 0.3),
            gold,
            hot,
            gold,
            gold.withValues(alpha: 0.25),
            gold.withValues(alpha: 0),
          ],
          stops: const [0, 0.045, 0.075, 0.105, 0.2, 0.245],
        ).createShader(bounds),
        LinearGradient(
          colors: [hot.withValues(alpha: 0), hot, hot.withValues(alpha: 0)],
          stops: const [0.045, 0.075, 0.105],
        ).createShader(bounds),
      ),
      SettloArcPlacement.home => (
        LinearGradient(
          colors: [
            gold.withValues(alpha: 0),
            gold.withValues(alpha: 0.3),
            gold,
            hot,
            gold,
            gold.withValues(alpha: 0.25),
            gold.withValues(alpha: 0),
          ],
          stops: const [0.48, 0.54, 0.61, 0.69, 0.79, 0.92, 1],
        ).createShader(bounds),
        LinearGradient(
          colors: [hot.withValues(alpha: 0), hot, hot.withValues(alpha: 0)],
          stops: const [0.61, 0.69, 0.79],
        ).createShader(bounds),
      ),
    };

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

    if (paths.$1 case final topArc?) {
      drawGlowingArc(topArc, topShader, topHotShader);
    }
    drawGlowingArc(paths.$2, bottomShader, bottomHotShader);
  }

  @override
  bool shouldRepaint(WelcomeBackgroundPainter oldDelegate) =>
      oldDelegate.background != background ||
      oldDelegate.gold != gold ||
      oldDelegate.highlight != highlight ||
      oldDelegate.placement != placement;
}
