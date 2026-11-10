import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:settlo_auth/src/widgets.dart';
import 'package:settlo_core/settlo_core.dart';

/// Welcome: the owner-approved, dark introduction to Settlo.
class WelcomeScreen extends StatefulWidget {
  /// The Welcome screen.
  const new({super.key});

  @override
  State<WelcomeScreen> createState() => _WelcomeScreenState();
}

class _WelcomeScreenState extends State<WelcomeScreen> {
  bool _busy = false;

  void _continue() {
    // Two taps can arrive before Flutter rebuilds a disabled button, so the
    // guard must flip synchronously before navigation.
    if (_busy) return;
    _busy = true;
    context.go(SettloRoutes.phone);
  }

  @override
  Widget build(BuildContext context) {
    // The welcome art direction is deliberately dark in both system themes.
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle.light,
      child: Theme(
        data: SettloTheme.dark(),
        child: Builder(
          builder: (context) {
            final colors = SettloColors.of(context);
            return Scaffold(
              body: Stack(
                children: [
                  Positioned.fill(
                    child: ExcludeSemantics(
                      child: CustomPaint(
                        painter: _WelcomeBackgroundPainter(
                          background: colors.background,
                          gold: colors.action,
                          highlight: colors.textPrimary,
                        ),
                      ),
                    ),
                  ),
                  SafeArea(
                    child: LayoutBuilder(
                      builder: (context, constraints) => SingleChildScrollView(
                        padding: const EdgeInsets.all(SettloSpacing.x3),
                        child: ConstrainedBox(
                          constraints: BoxConstraints(
                            minHeight: math.max(
                              0,
                              constraints.maxHeight - SettloSpacing.x6,
                            ),
                          ),
                          child: IntrinsicHeight(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                const Align(
                                  alignment: Alignment.centerLeft,
                                  child: SettloMark(size: 30),
                                ),
                                SizedBox(
                                  height: constraints.maxHeight >= 820
                                      ? 136
                                      : 96,
                                ),
                                Semantics(
                                  header: true,
                                  child: Text(
                                    'Money between friends,\nfinally settled.',
                                    style: SettloTypography.figtree(
                                      31,
                                      color: colors.textPrimary,
                                    ).copyWith(height: 1.13),
                                  ),
                                ),
                                const SizedBox(height: SettloSpacing.x2),
                                Text(
                                  'Flatmates, trips, and the ₹10 lakh you lent '
                                  'your '
                                  'friend — one quiet ledger you both can see.',
                                  style: SettloTypography.figtree(
                                    15,
                                    color: colors.textSecondary,
                                  ).copyWith(height: 1.5),
                                ),
                                const SizedBox(height: SettloSpacing.x5),
                                const _AvatarStack(),
                                const SizedBox(height: SettloSpacing.x5),
                                const _ExampleCard(
                                  semanticsLabel:
                                      'Example: Rahul owes you 750 rupees. '
                                      'Flat 402, groceries, wifi.',
                                  initial: 'R',
                                  title: 'Rahul owes you',
                                  detail: 'Flat 402 · groceries, wifi',
                                  amount: '₹750',
                                ),
                                const SizedBox(height: 12),
                                const _ExampleCard(
                                  semanticsLabel:
                                      'Example: Arjun repaid 25,000 rupees. '
                                      '13 of 40, on schedule.',
                                  initial: 'A',
                                  title: 'Arjun repaid',
                                  detail: '13 of 40 · on schedule',
                                  amount: '₹25,000',
                                ),
                                const Spacer(),
                                const SizedBox(height: SettloSpacing.x4),
                                Theme(
                                  data: Theme.of(context).copyWith(
                                    filledButtonTheme: FilledButtonThemeData(
                                      style: Theme.of(context)
                                          .filledButtonTheme
                                          .style
                                          ?.copyWith(
                                            backgroundColor:
                                                WidgetStatePropertyAll<Color>(
                                                  colors.welcomeAction,
                                                ),
                                          ),
                                    ),
                                  ),
                                  child: AuthButton(
                                    label: 'Continue with phone number',
                                    arrow: true,
                                    onPressed: _continue,
                                  ),
                                ),
                                const SizedBox(height: 14),
                                Text(
                                  'No email. No password. Your number is your '
                                  'account.',
                                  textAlign: TextAlign.center,
                                  style: SettloTypography.figtree(
                                    12,
                                    color: colors.textMuted,
                                  ),
                                ),
                                const SizedBox(height: SettloSpacing.x6),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            );
          },
        ),
      ),
    );
  }
}

class _AvatarStack extends StatelessWidget {
  const new();

  static const double _size = SettloWelcomeMetrics.avatar;
  static const double _step =
      SettloWelcomeMetrics.avatar - SettloWelcomeMetrics.avatarOverlap;

  @override
  Widget build(BuildContext context) {
    final colors = SettloColors.of(context);
    return Semantics(
      label: 'A group of friends',
      image: true,
      excludeSemantics: true,
      child: SizedBox(
        width: _size + (_step * 4),
        height: _size,
        child: Stack(
          clipBehavior: Clip.none,
          children: [
            const _Portrait(left: 0, asset: 'assets/welcome/avatar_rahul.webp'),
            const _Portrait(
              left: _step,
              asset: 'assets/welcome/avatar_friend.webp',
            ),
            Positioned(
              left: _step * 2,
              child: _AvatarCircle(
                borderColor: colors.textSecondary,
                child: Text(
                  'A',
                  style: SettloTypography.figtree(
                    20,
                    color: colors.textPrimary,
                  ),
                ),
              ),
            ),
            const _Portrait(
              left: _step * 3,
              asset: 'assets/welcome/avatar_arjun.webp',
            ),
            Positioned(
              left: _step * 4,
              child: _AvatarCircle(
                borderColor: colors.action,
                borderWidth: 1.75,
                child: Text(
                  '+',
                  style: SettloTypography.figtree(
                    30,
                    weight: FontWeight.w500,
                    color: colors.action,
                  ).copyWith(height: 1),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Portrait extends StatelessWidget {
  const new({required this.left, required this.asset});

  final double left;
  final String asset;

  @override
  Widget build(BuildContext context) => Positioned(
    left: left,
    child: _AvatarCircle(
      borderColor: SettloColors.of(context).textSecondary,
      child: ClipOval(
        child: Image.asset(
          asset,
          package: 'settlo_auth',
          width: SettloWelcomeMetrics.avatar,
          height: SettloWelcomeMetrics.avatar,
          fit: BoxFit.cover,
          excludeFromSemantics: true,
        ),
      ),
    ),
  );
}

class _AvatarCircle extends StatelessWidget {
  const new({
    required this.borderColor,
    required this.child,
    this.borderWidth = SettloWelcomeMetrics.avatarRing,
  });

  final Color borderColor;
  final Widget child;
  final double borderWidth;

  @override
  Widget build(BuildContext context) => Container(
    width: SettloWelcomeMetrics.avatar,
    height: SettloWelcomeMetrics.avatar,
    alignment: Alignment.center,
    decoration: BoxDecoration(
      color: SettloColors.of(context).surfaceHighest,
      shape: BoxShape.circle,
      border: Border.all(color: borderColor, width: borderWidth),
    ),
    child: child,
  );
}

class _ExampleCard extends StatelessWidget {
  const new({
    required this.semanticsLabel,
    required this.initial,
    required this.title,
    required this.detail,
    required this.amount,
  });

  final String semanticsLabel;
  final String initial;
  final String title;
  final String detail;
  final String amount;

  @override
  Widget build(BuildContext context) {
    final colors = SettloColors.of(context);
    final largeText = MediaQuery.textScalerOf(context).scale(1) > 1.4;
    return Semantics(
      container: true,
      label: semanticsLabel,
      excludeSemantics: true,
      child: Container(
        constraints: const BoxConstraints(
          minHeight: SettloWelcomeMetrics.exampleCardHeight,
        ),
        padding: const EdgeInsets.symmetric(
          horizontal: SettloSpacing.x2,
          vertical: 12,
        ),
        decoration: BoxDecoration(
          color: colors.surface,
          borderRadius: BorderRadius.circular(
            SettloWelcomeMetrics.exampleCardRadius,
          ),
          border: Border.all(color: colors.hairline),
        ),
        child: Row(
          children: [
            Container(
              width: 36,
              height: 36,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: colors.surfaceHighest,
                shape: BoxShape.circle,
              ),
              child: Text(
                initial,
                style: SettloTypography.figtree(14, color: colors.textPrimary),
              ),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: SettloTypography.figtree(
                      14,
                      color: colors.textPrimary,
                    ),
                  ),
                  Text(
                    detail,
                    style: SettloTypography.figtree(
                      12,
                      color: colors.textSecondary,
                    ),
                  ),
                  if (largeText) ...[
                    const SizedBox(height: SettloSpacing.half),
                    Text(
                      amount,
                      style: SettloTypography.figtree(
                        16,
                        color: colors.textPrimary,
                      ),
                    ),
                  ],
                ],
              ),
            ),
            if (!largeText) ...[
              const SizedBox(width: SettloSpacing.x1),
              Text(
                amount,
                style: SettloTypography.figtree(16, color: colors.textPrimary),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _WelcomeBackgroundPainter extends CustomPainter {
  const new({
    required this.background,
    required this.gold,
    required this.highlight,
  });

  final Color background;
  final Color gold;
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
  bool shouldRepaint(_WelcomeBackgroundPainter oldDelegate) =>
      oldDelegate.background != background ||
      oldDelegate.gold != gold ||
      oldDelegate.highlight != highlight;
}
