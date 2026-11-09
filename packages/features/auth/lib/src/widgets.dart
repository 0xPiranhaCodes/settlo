import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:settlo_core/settlo_core.dart';

/// The line glyphs the sign-in artboards use, on a 24-unit grid.
enum AuthGlyph {
  /// Back chevron.
  back,

  /// Arrow on the primary buttons.
  arrow,

  /// Speech bubble beside the SMS note.
  message,

  /// Shield with a tick beside the code-safety note.
  shield,

  /// The two bars of the mark on Welcome.
  mark,
}

/// [glyph] at [size] in [color], stroked [stroke] units wide on the 24 grid.
class AuthIcon extends StatelessWidget {
  /// An icon drawing [glyph].
  const new(
    this.glyph, {
    required this.color,
    this.size = 24,
    this.stroke = 1.6,
    super.key,
  });

  /// What to draw.
  final AuthGlyph glyph;

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

  final AuthGlyph glyph;
  final Color color;
  final double stroke;

  // Paths transcribed from the canvas SVGs (viewBox 0 0 24 24).
  Path get _path => switch (glyph) {
    AuthGlyph.back =>
      Path()
        ..moveTo(15, 5)
        ..lineTo(8, 12)
        ..lineTo(15, 19),
    AuthGlyph.arrow =>
      Path()
        ..moveTo(5, 12)
        ..lineTo(19, 12)
        ..moveTo(14, 7)
        ..lineTo(19, 12)
        ..lineTo(14, 17),
    AuthGlyph.message =>
      Path()
        ..moveTo(4, 5)
        ..lineTo(20, 5)
        ..lineTo(20, 16)
        ..lineTo(9, 16)
        ..lineTo(4, 20)
        ..close(),
    AuthGlyph.shield =>
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
    AuthGlyph.mark =>
      Path()
        ..moveTo(5, 9)
        ..lineTo(19, 9)
        ..moveTo(5, 15)
        ..lineTo(19, 15),
  };

  @override
  void paint(Canvas canvas, Size size) {
    final scale = size.width / 24;
    canvas
      ..save()
      ..scale(scale)
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

/// A full-screen sign-in step: [top] from the canvas's 60px line (or below
/// the status bar if that is lower), [content] in a column that scrolls
/// when the keyboard leaves too little room, and [bottom] pinned to the
/// foot with 28px under it.
///
/// [content] may use [Spacer] to push content down; it takes the room
/// left over and none when scrolling.
class AuthPage extends StatelessWidget {
  /// A page laying out [top], [content] and [bottom].
  const new({
    required this.content,
    this.top,
    this.topInset = 16,
    this.bottom,
    this.bottomInset = 28,
    super.key,
  });

  /// Pinned to the top: the step header or the wordmark.
  final Widget? top;

  /// Space between the status bar line (44, or the device's top inset if
  /// larger) and [top].
  final double topInset;

  /// The page body, 24px from each side.
  final List<Widget> content;

  /// The primary action at the foot.
  final Widget? bottom;

  /// Space under [bottom] (or under [content] without one).
  final double bottomInset;

  @override
  Widget build(BuildContext context) {
    final media = MediaQuery.of(context);
    final topPad = math.max(media.padding.top, 44) + topInset;
    final bottomPad = math.max(bottomInset, media.padding.bottom + 8);
    return Scaffold(
      body: CustomScrollView(
        slivers: [
          SliverFillRemaining(
            hasScrollBody: false,
            child: Padding(
              padding: EdgeInsets.only(top: topPad, bottom: bottomPad),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  ?top,
                  Expanded(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: SettloSpacing.x3,
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [...content, ?bottom],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// The Phone and OTP header: a round back button and the step count.
class StepHeader extends StatelessWidget {
  /// A header for step [step] of [of].
  const new({required this.step, required this.of, super.key});

  /// This step, from 1.
  final int step;

  /// Number of steps.
  final int of;

  @override
  Widget build(BuildContext context) {
    final c = SettloColors.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: SettloSpacing.screenMargin,
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Semantics(
            button: true,
            label: 'Back',
            child: InkWell(
              onTap: () => goBack(context),
              customBorder: const CircleBorder(),
              child: Container(
                width: SettloSpacing.minTouchTarget,
                height: SettloSpacing.minTouchTarget,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: c.surface,
                  shape: BoxShape.circle,
                  border: Border.all(color: c.hairline),
                ),
                child: AuthIcon(AuthGlyph.back, color: c.textPrimary, size: 22),
              ),
            ),
          ),
          Text(
            '$step of $of',
            style: SettloTypography.figtree(13, color: c.textSecondary),
          ),
        ],
      ),
    );
  }

  /// Pops to the previous step, or goes to Welcome when opened directly.
  static void goBack(BuildContext context) {
    final router = GoRouter.of(context);
    if (router.canPop()) {
      router.pop();
    } else {
      router.go(SettloRoutes.welcome);
    }
  }
}

/// A 56px primary action across the page (canvas buttons are 56 tall).
class AuthButton extends StatelessWidget {
  /// A button labelled [label]; null [onPressed] disables it.
  const new({
    required this.label,
    required this.onPressed,
    this.arrow = false,
    super.key,
  });

  /// Button text.
  final String label;

  /// Called on tap.
  final VoidCallback? onPressed;

  /// Whether the canvas arrow trails the label.
  final bool arrow;

  @override
  Widget build(BuildContext context) => SizedBox(
    height: 56,
    child: SPrimaryButton(
      label: label,
      onPressed: onPressed,
      icon: arrow
          ? Builder(
              builder: (context) => AuthIcon(
                AuthGlyph.arrow,
                color:
                    IconTheme.of(context).color ??
                    SettloColors.of(context).onAction,
                size: 18,
                stroke: 1.9,
              ),
            )
          : null,
    ),
  );
}

/// Title and subtitle at the head of a step.
class StepTitle extends StatelessWidget {
  /// [title] over [subtitle].
  const new({
    required this.title,
    required this.subtitle,
    this.gap = 10,
    super.key,
  });

  /// 30px title.
  final String title;

  /// 15px secondary line under it.
  final Widget subtitle;

  /// Space between them.
  final double gap;

  @override
  Widget build(BuildContext context) {
    final c = SettloColors.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Semantics(
          header: true,
          child: Text(
            title,
            style: SettloTypography.figtree(
              30,
              weight: FontWeight.w500,
              letterSpacing: -0.8,
              color: c.textPrimary,
            ).copyWith(height: 1.15),
          ),
        ),
        SizedBox(height: gap),
        DefaultTextStyle(
          style: SettloTypography.figtree(
            15,
            color: c.textSecondary,
          ).copyWith(height: 1.5),
          child: subtitle,
        ),
      ],
    );
  }
}

/// A plain, sentence-case error under a field, read out when it appears.
class AuthErrorText extends StatelessWidget {
  /// Shows [message].
  const new(this.message, {super.key});

  /// What went wrong and what to do.
  final String message;

  @override
  Widget build(BuildContext context) => Semantics(
    liveRegion: true,
    child: Text(
      message,
      style: SettloTypography.figtree(
        13,
        color: SettloColors.of(context).textPrimary,
      ).copyWith(height: 1.4),
    ),
  );
}
