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

  /// `₹—` in secondary grey: a balance that is not known yet, such as
  /// before recorded claims are reviewed.
  const new blank({this.size = 15, super.key})
    : amount = null,
      tone = MoneyTone.settled,
      signed = false;

  /// The amount; null for [MoneyText.blank].
  final Paise? amount;

  /// Which way the money points.
  final MoneyTone tone;

  /// Font size of the number.
  final double size;

  /// Whether positive amounts get a `+`.
  final bool signed;

  @override
  Widget build(BuildContext context) {
    final amount = this.amount;
    final text = amount == null
        ? '₹—'
        : formatInr(amount, signed: signed).replaceFirst('-', '−');
    // Read aloud in rupees, in words, at every size: a screen reader would
    // otherwise say the glyphs ("plus rupee six comma seventy-four…").
    final spoken = amount == null
        ? 'not known yet'
        : spokenInr(amount, signed: signed);
    final color = SettloColors.of(context).money(tone);
    final style = SettloTypography.amount(size, color: color);
    if (size < SettloTypography.serifFrom) {
      return Semantics(
        label: spoken,
        excludeSemantics: true,
        child: Text(text, style: style, maxLines: 1, softWrap: false),
      );
    }
    final rupee = text.indexOf('₹');
    assert(rupee >= 0, 'formatInr always includes ₹');
    // The raise and gap are in ems of the number as rendered, so they
    // follow the system text scale.
    final em = MediaQuery.textScalerOf(context).scale(size);
    final symbol = SettloTypography.figtree(
      size * 0.56,
      weight: FontWeight.w500,
      letterSpacing: 0,
      color: color,
    ).copyWith(height: 1);
    return Semantics(
      label: spoken,
      excludeSemantics: true,
      child: Text.rich(
        TextSpan(
          children: [
            TextSpan(text: text.substring(0, rupee)),
            WidgetSpan(
              alignment: PlaceholderAlignment.baseline,
              baseline: TextBaseline.alphabetic,
              child: Transform.translate(
                offset: Offset(0, -0.26 * em),
                child: Padding(
                  padding: EdgeInsets.only(right: 0.06 * em),
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
