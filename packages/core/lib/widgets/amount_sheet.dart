import 'package:flutter/material.dart';
import 'package:settlo_core/theme/colors.dart';
import 'package:settlo_core/theme/tokens.dart';
import 'package:settlo_core/theme/typography.dart';

/// Font size of the amount at the top of an amount-entry sheet.
const double _amountSize = 52;

/// The frame of an amount-entry sheet (add expense, new loan, settle up):
/// drag handle, close button and title, then the amount first and in the
/// serif, then [body], then [action] pinned to the bottom.
///
/// Show it with [showSAmountSheet].
class SAmountSheet extends StatelessWidget {
  /// A sheet titled [title] around [amount] and [body].
  const new({
    required this.title,
    required this.amount,
    required this.onClose,
    this.amountLabel = 'Amount',
    this.body,
    this.action,
    super.key,
  });

  /// Header text, such as `New expense · Flat 402`.
  final String title;

  /// The amount, usually a field or text holding just the number. It
  /// inherits IBM Plex Serif 500 at 52 in primary text; the ₹ before it
  /// is drawn by the sheet.
  final Widget amount;

  /// Small caps label above the amount.
  final String amountLabel;

  /// Called by the close button.
  final VoidCallback onClose;

  /// Everything below the amount.
  final Widget? body;

  /// The sheet's primary action, such as `Save expense`.
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    final c = SettloColors.of(context);
    final text = Theme.of(context).textTheme;
    const radius = Radius.circular(SettloRadius.cardHero);
    // The specular edge is a line clipped by the top corners: Flutter
    // cannot round a border drawn on one side only.
    return ClipRRect(
      borderRadius: const BorderRadius.vertical(top: radius),
      child: ColoredBox(
        color: c.surface,
        child: Stack(
          children: [
            Positioned.fill(
              child: SafeArea(
                top: false,
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: SettloSpacing.screenMargin,
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Center(
                        child: Container(
                          width: 36,
                          height: 4,
                          margin: const EdgeInsets.only(top: 10),
                          decoration: BoxDecoration(
                            color: c.surfaceHighest,
                            borderRadius: BorderRadius.circular(2),
                          ),
                        ),
                      ),
                      const SizedBox(height: 10),
                      Row(
                        children: [
                          Transform.translate(
                            offset: const Offset(-12, 0),
                            child: Semantics(
                              button: true,
                              label: 'Close',
                              excludeSemantics: true,
                              child: GestureDetector(
                                behavior: HitTestBehavior.opaque,
                                onTap: onClose,
                                child: SizedBox.square(
                                  dimension: SettloSpacing.minTouchTarget,
                                  child: Center(
                                    child: CustomPaint(
                                      size: const Size.square(22),
                                      painter: _CrossPainter(c.textPrimary),
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          ),
                          Expanded(
                            child: Text(
                              title,
                              textAlign: TextAlign.center,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: text.titleSmall,
                            ),
                          ),
                          const SizedBox(
                            width: SettloSpacing.minTouchTarget - 12,
                          ),
                        ],
                      ),
                      const SizedBox(height: 22),
                      Text(
                        amountLabel.toUpperCase(),
                        textAlign: TextAlign.center,
                        style: text.labelMedium?.copyWith(
                          color: c.textSecondary,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Padding(
                            padding: const EdgeInsets.only(top: 6, right: 6),
                            child: Text(
                              '₹',
                              style: SettloTypography.figtree(
                                28,
                                weight: FontWeight.w500,
                                color: c.textSecondary,
                              ),
                            ),
                          ),
                          Flexible(
                            child: DefaultTextStyle(
                              style: SettloTypography.amount(
                                _amountSize,
                                color: c.textPrimary,
                              ).copyWith(letterSpacing: -1.5),
                              maxLines: 1,
                              child: amount,
                            ),
                          ),
                        ],
                      ),
                      if (body case final body?) ...[
                        const SizedBox(height: 18),
                        Expanded(child: body),
                      ] else
                        const Spacer(),
                      if (action case final action?)
                        Padding(
                          padding: const EdgeInsets.only(
                            top: SettloSpacing.x2,
                            bottom: 26,
                          ),
                          child: action,
                        ),
                    ],
                  ),
                ),
              ),
            ),
            Positioned(
              top: 0,
              left: 0,
              right: 0,
              height: SettloElevation.hairline,
              child: ColoredBox(color: c.specular),
            ),
          ],
        ),
      ),
    );
  }
}

/// Shows [builder]'s [SAmountSheet] as a modal bottom sheet that rises to
/// 54px below the top of the screen, as on the canvas.
Future<T?> showSAmountSheet<T>({
  required BuildContext context,
  required WidgetBuilder builder,
}) {
  final c = SettloColors.of(context);
  return showModalBottomSheet<T>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    backgroundColor: Colors.transparent,
    barrierColor: c.background.withValues(alpha: 0.6),
    elevation: 0,
    builder: (context) => Padding(
      padding: EdgeInsets.only(
        top: 54 - MediaQuery.paddingOf(context).top.clamp(0, 54),
        bottom: MediaQuery.viewInsetsOf(context).bottom,
      ),
      child: builder(context),
    ),
  );
}

/// The canvas close icon: an X in a 24 box, stroke 1.6, round caps.
class _CrossPainter extends CustomPainter {
  const new(this.color);

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final scale = size.width / 24;
    final paint = Paint()
      ..color = color
      ..strokeWidth = 1.6 * scale
      ..strokeCap = StrokeCap.round;
    canvas
      ..drawLine(
        const Offset(6, 6) * scale,
        const Offset(18, 18) * scale,
        paint,
      )
      ..drawLine(
        const Offset(18, 6) * scale,
        const Offset(6, 18) * scale,
        paint,
      );
  }

  @override
  bool shouldRepaint(_CrossPainter old) => old.color != color;
}
