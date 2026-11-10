import 'dart:async';
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
    unawaited(HapticFeedback.lightImpact());
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
                        painter: WelcomeBackgroundPainter(
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
                                _WelcomeActionButton(onPressed: _continue),
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

class _WelcomeActionButton extends StatefulWidget {
  const new({required this.onPressed});

  final VoidCallback onPressed;

  @override
  State<_WelcomeActionButton> createState() => _WelcomeActionButtonState();
}

class _WelcomeActionButtonState extends State<_WelcomeActionButton> {
  bool _pressed = false;

  void _setPressed(bool value) {
    if (_pressed == value) return;
    setState(() => _pressed = value);
  }

  @override
  Widget build(BuildContext context) {
    final colors = SettloColors.of(context);
    final reduceMotion = MediaQuery.disableAnimationsOf(context);
    final pressed = _pressed && !reduceMotion;
    final duration = reduceMotion
        ? Duration.zero
        : SettloWelcomeMetrics.actionPressDuration;

    return SizedBox(
      height: 56,
      child: AnimatedScale(
        key: const ValueKey('welcome-action-scale'),
        scale: pressed ? SettloWelcomeMetrics.actionPressedScale : 1,
        duration: duration,
        curve: Curves.easeOutCubic,
        child: DecoratedBox(
          decoration: BoxDecoration(
            borderRadius: const BorderRadius.all(
              Radius.circular(SettloRadius.button),
            ),
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [colors.welcomeActionTop, colors.welcomeActionBottom],
            ),
            boxShadow: [
              BoxShadow(
                color: colors.welcomeActionShadow,
                offset: const Offset(
                  0,
                  SettloWelcomeMetrics.actionShadowOffset,
                ),
                blurRadius: SettloWelcomeMetrics.actionShadowBlur,
              ),
            ],
          ),
          child: Stack(
            fit: StackFit.expand,
            children: [
              Listener(
                onPointerDown: (_) => _setPressed(true),
                onPointerUp: (_) => _setPressed(false),
                onPointerCancel: (_) => _setPressed(false),
                child: FilledButton(
                  onPressed: widget.onPressed,
                  style:
                      FilledButton.styleFrom(
                        backgroundColor: Colors.transparent,
                        foregroundColor: SettloColors.dark.onAction,
                        shadowColor: Colors.transparent,
                        disabledBackgroundColor: Colors.transparent,
                        padding: const EdgeInsets.symmetric(
                          horizontal: SettloSpacing.x2,
                        ),
                        shape: const RoundedRectangleBorder(
                          borderRadius: BorderRadius.all(
                            Radius.circular(SettloRadius.button),
                          ),
                        ),
                      ).copyWith(
                        overlayColor: const WidgetStatePropertyAll(
                          Colors.transparent,
                        ),
                      ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Flexible(
                        child: Text(
                          'Continue with phone number',
                          overflow: TextOverflow.ellipsis,
                          style: SettloTypography.figtree(
                            15,
                            weight: FontWeight.w600,
                            color: SettloColors.dark.onAction,
                          ),
                        ),
                      ),
                      const SizedBox(width: SettloSpacing.x1),
                      AnimatedSlide(
                        key: const ValueKey('welcome-action-arrow'),
                        offset: Offset(
                          pressed
                              ? SettloWelcomeMetrics.actionArrowNudge / 18
                              : 0,
                          0,
                        ),
                        duration: duration,
                        curve: Curves.easeOutCubic,
                        child: const AuthIcon(
                          AuthGlyph.arrow,
                          color: Color(0xFF0A0B0D),
                          size: 18,
                          stroke: 1.9,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              Positioned(
                top: 0,
                left: SettloSpacing.x2,
                right: SettloSpacing.x2,
                child: IgnorePointer(
                  child: Container(
                    height: SettloElevation.hairline,
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(
                        SettloElevation.hairline,
                      ),
                      gradient: LinearGradient(
                        colors: [
                          colors.welcomeActionHighlight.withValues(alpha: 0),
                          colors.welcomeActionHighlight,
                          colors.welcomeActionHighlight.withValues(alpha: 0),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
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
