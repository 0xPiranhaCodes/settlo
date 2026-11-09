import 'package:flutter/widgets.dart';
import 'package:settlo_core/money/format.dart';
import 'package:settlo_core/money/paise.dart';
import 'package:settlo_core/theme/colors.dart';
import 'package:settlo_core/theme/typography.dart';

/// An amount of money in the tone's colour.
///
/// From [SettloTypography.serifFrom] up, the number is IBM Plex Serif and
/// the ₹ is Figtree at 56% of the number, raised towards the cap height
/// (canvas: `0.56em`, `vertical-align: 0.26em`). Below that the whole amount
/// is Figtree, as list amounts are on the canvas. Negative amounts use a
/// true minus sign.
class MoneyText extends StatelessWidget {
  /// Shows [amount] at [size] in [tone]; [signed] adds `+` to positive
  /// amounts.
  const new(
    this.amount, {
    this.tone = MoneyTone.neutral,
    this.size = 15,
    this.signed = false,
    super.key,
  });

  /// The amount.
  final Paise amount;

  /// Which way the money points.
  final MoneyTone tone;

  /// Font size of the number.
  final double size;

  /// Whether positive amounts get a `+`.
  final bool signed;

  @override
  Widget build(BuildContext context) {
    final text = formatInr(amount, signed: signed).replaceFirst('-', '−');
    final color = SettloColors.of(context).money(tone);
    final style = SettloTypography.amount(size, color: color);
    if (size < SettloTypography.serifFrom) {
      return Text(text, style: style, maxLines: 1, softWrap: false);
    }
    final rupee = text.indexOf('₹');
    final symbol = SettloTypography.figtree(
      size * 0.56,
      weight: FontWeight.w500,
      letterSpacing: 0,
      color: color,
    ).copyWith(height: 1);
    return Semantics(
      label: text,
      excludeSemantics: true,
      child: Text.rich(
        TextSpan(
          children: [
            TextSpan(text: text.substring(0, rupee)),
            WidgetSpan(
              alignment: PlaceholderAlignment.baseline,
              baseline: TextBaseline.alphabetic,
              child: Transform.translate(
                offset: Offset(0, -0.26 * size),
                child: Padding(
                  padding: EdgeInsets.only(right: 0.06 * size),
                  child: Text('₹', style: symbol),
                ),
              ),
            ),
            TextSpan(text: text.substring(rupee + 1)),
          ],
        ),
        style: style,
        maxLines: 1,
        softWrap: false,
      ),
    );
  }
}
