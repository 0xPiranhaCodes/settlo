import 'package:settlo_core/money/paise.dart';

/// Formats [amount] as INR with Indian digit grouping.
///
/// `₹6,74,200` for whole rupees, `₹420.50` when there are paise. Negative
/// amounts are prefixed with `-`; with [signed] positive amounts get `+`.
/// Zero never has a sign.
String formatInr(Paise amount, {bool signed = false}) {
  final v = amount.value;
  final rupees = (v.abs() ~/ 100).toString();
  final paise = v.abs() % 100;
  final cut = rupees.length - 3;
  // Indian grouping: last three digits, then pairs (6,74,200).
  final grouped = cut <= 0
      ? rupees
      : '${rupees.substring(0, cut).replaceAll(_pairs, ',')},'
            '${rupees.substring(cut)}';
  final body = paise == 0
      ? '₹$grouped'
      : '₹$grouped.${paise.toString().padLeft(2, '0')}';
  if (v < 0) return '-$body';
  return signed && v > 0 ? '+$body' : body;
}

/// [amount] in English words using the Indian system (lakh, crore).
///
/// `₹10,00,000` is `ten lakh rupees`; `₹1,250.50` is
/// `one thousand two hundred fifty rupees and fifty paise`.
/// Throws [ArgumentError] for negative amounts.
String amountInWords(Paise amount) {
  final v = amount.value;
  if (v < 0) throw ArgumentError.value(amount, 'amount', 'must be >= 0');
  final rupees = v ~/ 100;
  final paise = v % 100;
  final r = '${_words(rupees)} ${rupees == 1 ? 'rupee' : 'rupees'}';
  final p = '${_words(paise)} ${paise == 1 ? 'paisa' : 'paise'}';
  if (paise == 0) return r;
  return rupees == 0 ? p : '$r and $p';
}

final _pairs = RegExp(r'\B(?=(\d{2})+$)');

const _ones = [
  'zero', 'one', 'two', 'three', 'four', 'five', 'six', 'seven', 'eight', //
  'nine', 'ten', 'eleven', 'twelve', 'thirteen', 'fourteen', 'fifteen',
  'sixteen', 'seventeen', 'eighteen', 'nineteen',
];
const _tens = [
  '', '', 'twenty', 'thirty', 'forty', 'fifty', 'sixty', 'seventy', //
  'eighty', 'ninety',
];

String _words(int n) {
  String scaled(int unit, String name) {
    final rest = n % unit;
    final head = '${_words(n ~/ unit)} $name';
    return rest == 0 ? head : '$head ${_words(rest)}';
  }

  if (n >= 10000000) return scaled(10000000, 'crore');
  if (n >= 100000) return scaled(100000, 'lakh');
  if (n >= 1000) return scaled(1000, 'thousand');
  if (n >= 100) return scaled(100, 'hundred');
  if (n >= 20) {
    return n % 10 == 0 ? _tens[n ~/ 10] : '${_tens[n ~/ 10]}-${_ones[n % 10]}';
  }
  return _ones[n];
}
