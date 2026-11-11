import 'dart:async';

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:settlo_core/theme/colors.dart';
import 'package:settlo_core/theme/tokens.dart';
import 'package:settlo_core/theme/typography.dart';
import 'package:settlo_core/widgets/confirm.dart';
import 'package:settlo_core/widgets/pressable.dart';
import 'package:settlo_core/widgets/scroll_scaffold.dart';
import 'package:settlo_core/widgets/sheet.dart';

/// Font size of the amount at the top of an amount-entry sheet.
const double _amountSize = 52;

/// The frame of an amount-entry sheet (add expense, new loan, settle up):
/// drag handle, close button and title, then an optional [header], the
/// amount in Figtree, then [body], then [action] pinned to the bottom.
///
/// Show it with [showSAmountSheet].
class SAmountSheet extends StatefulWidget {
  /// A sheet titled [title] around [amount] and [body].
  const new({
    required this.title,
    required this.amount,
    required this.onClose,
    this.amountLabel = 'Amount',
    this.header,
    this.body,
    this.action,
    this.dirty = false,
    this.saving = false,
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

  /// Input the user has not saved. On iOS, Close or a drag down then asks
  /// before discarding it.
  final bool dirty;

  /// A save is in flight. On iOS the sheet then stays put: closing it now
  /// would pop again once the save lands.
  final bool saving;

  @override
  State<SAmountSheet> createState() => _SAmountSheetState();
}

class _SAmountSheetState extends State<SAmountSheet> {
  double _drag = 0;
  bool _dragging = false;
  bool _dismissed = false;
  String get title => widget.title;
  String get amountLabel => widget.amountLabel;
  Widget get amount => widget.amount;
  Widget? get body => widget.body;
  Widget? get header => widget.header;
  Widget? get action => widget.action;
  VoidCallback get onClose => widget.onClose;

  /// Android keeps closing straight away, as before.
  bool get _guarded =>
      Theme.of(context).platform == TargetPlatform.iOS &&
      (widget.dirty || widget.saving);
  bool _asking = false;

  /// Closes, first asking whether to discard unsaved input.
  Future<void> _close() async {
    if (!_guarded) return onClose();
    if (_dismissed || _asking || widget.saving) return;
    _asking = true;
    final discard = await showSettloActionSheet(
      context: context,
      title: 'Discard changes?',
      destructive: 'Discard',
      cancel: 'Keep editing',
    );
    _asking = false;
    if (discard != true || !mounted || _dismissed) return;
    _dismissed = true;
    onClose();
  }

  void _endDrag(DragEndDetails details) {
    if (_dismissed) return;
    if (_drag > 100 || (details.primaryVelocity ?? 0) > 700) {
      if (!_guarded) {
        _dismissed = true;
        return onClose();
      }
      setState(() {
        _dragging = false;
        _drag = 0;
      });
      unawaited(_close());
    } else {
      setState(() {
        _dragging = false;
        _drag = 0;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = SettloColors.of(context);
    final text = Theme.of(context).textTheme;
    const radius = Radius.circular(SettloRadius.cardHero);
    // The specular edge is a line clipped by the top corners: Flutter
    // cannot round a border drawn on one side only.
    final largeText = MediaQuery.textScalerOf(context).scale(14) > 21;
    final titleRow = Row(
      children: [
        Transform.translate(
          offset: const Offset(-12, 0),
          child: SPressable(
            onTap: _close,
            label: 'Close',
            ringRadius: BorderRadius.circular(SettloSpacing.minTouchTarget / 2),
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
          child: FittedBox(
            fit: BoxFit.scaleDown,
            child: Text(
              title,
              textAlign: TextAlign.center,
              maxLines: 1,
              overflow: largeText
                  ? TextOverflow.visible
                  : TextOverflow.ellipsis,
              style: text.titleLarge,
            ),
          ),
        ),
        const SizedBox(width: SettloSpacing.minTouchTarget - 12),
      ],
    );
    // Inside an iOS task sheet the route owns drag to dismiss.
    final routeDrags = CupertinoSheetRoute.hasParentSheet(context);
    final navigation = GestureDetector(
      excludeFromSemantics: true,
      behavior: HitTestBehavior.opaque,
      onVerticalDragUpdate: routeDrags
          ? null
          : (details) => setState(() {
              _dragging = true;
              _drag = (_drag + details.delta.dy).clamp(0, double.infinity);
            }),
      onVerticalDragEnd: routeDrags ? null : _endDrag,
      onVerticalDragCancel: routeDrags
          ? null
          : () => setState(() {
              _dragging = false;
              _drag = 0;
            }),
      child: Column(
        mainAxisSize: MainAxisSize.min,
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
          titleRow,
        ],
      ),
    );
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
    final sheet = AnimatedContainer(
      duration: _dragging || MediaQuery.disableAnimationsOf(context)
          ? Duration.zero
          : SettloMotion.panel,
      curve: SettloMotion.curve,
      transform: Matrix4.translationValues(0, _drag, 0),
      decoration: BoxDecoration(
        color: c.surface,
        borderRadius: const BorderRadius.vertical(top: radius),
        border: Border.all(
          color: SettloElevation.border(
            dark: Theme.of(context).brightness == Brightness.dark,
          ),
        ),
        boxShadow: SettloElevation.ambient(
          dark: Theme.of(context).brightness == Brightness.dark,
        ),
      ),
      child: Column(
        children: [
          Expanded(
            child: ClipRRect(
              borderRadius: const BorderRadius.vertical(top: radius),
              child: SettloScrollScaffold(
                key: const ValueKey('amount-sheet-scroll'),
                title: title,
                statusInset: 0,
                expandedHeight: 108,
                compactHeader: titleRow,
                slivers: [
                  SliverFillRemaining(hasScrollBody: false, child: content),
                ],
                children: [navigation],
              ),
            ),
          ),
          // iOS's decimal keypad has no return key: a bar above it closes it.
          if (Theme.of(context).platform == TargetPlatform.iOS &&
              MediaQuery.viewInsetsOf(context).bottom > 0)
            const _KeyboardDone(),
        ],
      ),
    );
    return PopScope(
      canPop: !_guarded,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) unawaited(_close());
      },
      child: sheet,
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
  showDragHandle: false,
  builder: (context) => Padding(
    padding: EdgeInsets.only(
      top: 54 - MediaQuery.paddingOf(context).top.clamp(0, 54),
    ),
    child: builder(context),
  ),
);

/// Done above the keyboard, as a keyboard toolbar would show it.
class _KeyboardDone extends StatelessWidget {
  const new();

  @override
  Widget build(BuildContext context) {
    final c = SettloColors.of(context);
    return DecoratedBox(
      decoration: BoxDecoration(
        color: c.surfaceRaised,
        border: Border(top: BorderSide(color: c.hairline)),
      ),
      child: SizedBox(
        width: double.infinity,
        child: Align(
          alignment: Alignment.centerRight,
          child: CupertinoButton(
            key: const ValueKey('keyboard-done'),
            onPressed: () => FocusManager.instance.primaryFocus?.unfocus(),
            child: Text(
              'Done',
              style: SettloTypography.body(
                weight: FontWeight.w600,
                color: c.textPrimary,
              ),
            ),
          ),
        ),
      ),
    );
  }
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
  Widget build(BuildContext context) => Padding(
    padding: padding,
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: children,
    ),
  );
}
