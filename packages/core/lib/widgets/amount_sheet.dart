import 'package:flutter/material.dart';
import 'package:settlo_core/theme/colors.dart';
import 'package:settlo_core/theme/tokens.dart';
import 'package:settlo_core/theme/typography.dart';
import 'package:settlo_core/widgets/pressable.dart';
import 'package:settlo_core/widgets/sheet.dart';

/// Font size of the amount at the top of an amount-entry sheet.
const double _amountSize = 52;

/// The frame of an amount-entry sheet (add expense, new loan, settle up):
/// drag handle, close button and title, then an optional [header], the
/// amount in Figtree, then [body], then [action] pinned to the bottom.
///
/// Show it with [showSAmountSheet].
class SAmountSheet extends StatelessWidget {
  /// A sheet titled [title] around [amount] and [body].
  const new({
    required this.title,
    required this.amount,
    required this.onClose,
    this.amountLabel = 'Amount',
    this.header,
    this.body,
    this.action,
    super.key,
  });

  /// Header text, such as `New expense · Flat 402`.
  final String title;

  /// The amount, usually a field or text holding just the number. It
  /// inherits Figtree 500 at 52 in primary text; the ₹ before it is drawn
  /// by the sheet.
  final Widget amount;

  /// Small caps label above the amount.
  final String amountLabel;

  /// Above the amount's label, such as who pays whom.
  final Widget? header;

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
    final largeText = MediaQuery.textScalerOf(context).scale(14) > 21;
    final content = SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: SettloSpacing.screenMargin,
        ),
        child: Column(
          mainAxisSize: largeText ? MainAxisSize.min : MainAxisSize.max,
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
                  child: SPressable(
                    onTap: onClose,
                    label: 'Close',
                    ringRadius: BorderRadius.circular(
                      SettloSpacing.minTouchTarget / 2,
                    ),
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
                Expanded(
                  child: Text(
                    title,
                    textAlign: TextAlign.center,
                    maxLines: largeText ? null : 1,
                    overflow: largeText
                        ? TextOverflow.visible
                        : TextOverflow.ellipsis,
                    style: text.titleSmall,
                  ),
                ),
                const SizedBox(width: SettloSpacing.minTouchTarget - 12),
              ],
            ),
            const SizedBox(height: 22),
            if (header case final header?) ...[
              header,
              const SizedBox(height: 18),
            ],
            Text(
              amountLabel.toUpperCase(),
              textAlign: TextAlign.center,
              style: text.labelMedium?.copyWith(color: c.textSecondary),
            ),
            const SizedBox(height: 6),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                // The amount's own semantics say rupees.
                ExcludeSemantics(
                  child: Padding(
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
                ),
                Flexible(
                  child: DefaultTextStyle(
                    style: SettloTypography.amount(
                      _amountSize,
                      color: c.textPrimary,
                    ).copyWith(letterSpacing: -1.5),
                    maxLines: 1,
                    child: FittedBox(fit: BoxFit.scaleDown, child: amount),
                  ),
                ),
              ],
            ),
            if (body case final body?) ...[
              const SizedBox(height: 18),
              if (largeText) body else Expanded(child: body),
            ] else if (!largeText)
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
    );
    return ClipRRect(
      borderRadius: const BorderRadius.vertical(top: radius),
      child: ColoredBox(
        color: c.surface,
        child: Stack(
          children: [
            if (largeText)
              SingleChildScrollView(
                key: const ValueKey('amount-sheet-scroll'),
                child: content,
              )
            else
              Positioned.fill(child: content),
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

/// Shows [builder]'s [SAmountSheet] with [showSettloSheet], risen to 54px
/// below the top of the screen, as on the canvas.
Future<T?> showSAmountSheet<T>({
  required BuildContext context,
  required WidgetBuilder builder,
}) => showSettloSheet<T>(
  context: context,
  backgroundColor: Colors.transparent,
  builder: (context) => Padding(
    padding: EdgeInsets.only(
      top: 54 - MediaQuery.paddingOf(context).top.clamp(0, 54),
    ),
    child: builder(context),
  ),
);

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

/// A form body that joins its sheet's single scroll surface at large text.
/// At normal text it retains the pinned footer and independently scrolls.
class SFormBody extends StatelessWidget {
  /// Content in reading order.
  const new({
    required this.children,
    this.padding = EdgeInsets.zero,
    super.key,
  });

  /// Form fields and their labels.
  final List<Widget> children;

  /// Optional inner inset.
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) =>
      MediaQuery.textScalerOf(context).scale(14) > 21
      ? Padding(
          padding: padding,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisSize: MainAxisSize.min,
            children: children,
          ),
        )
      : ListView(padding: padding, children: children);
}
