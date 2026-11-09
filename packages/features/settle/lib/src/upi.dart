import 'package:settlo_core/settlo_core.dart';

/// [amount] in rupees with exactly two decimals, as UPI's `am` wants it:
/// 1 paisa is `0.01`, ₹3,650 is `3650.00`. No grouping, no ₹.
String upiAmount(Paise amount) {
  final v = amount.value;
  if (v <= 0) throw ArgumentError.value(amount, 'amount', 'must be > 0');
  return '${v ~/ 100}.${(v % 100).toString().padLeft(2, '0')}';
}

/// A UPI intent (`upi://pay`) that opens the payer's UPI app with [payee]'s
/// VPA, [name], [amount] and [note] filled in. The payer approves it
/// there; Settlo never moves money.
///
/// Every value is percent-encoded (a space is `%20`, never `+`, which some
/// UPI apps show literally).
Uri upiPayUri({
  required String payee,
  required String name,
  required Paise amount,
  required String note,
}) {
  String field(String key, String value) =>
      '$key=${Uri.encodeComponent(value)}';
  return Uri.parse(
    'upi://pay?${[field('pa', payee), field('pn', name), field('am', upiAmount(amount)), 'cu=INR', field('tn', note)].join('&')}',
  );
}
