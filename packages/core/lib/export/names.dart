import 'package:settlo_core/supabase/spaces.dart';

final _phoneLike = RegExp(r'^\+?[\d\s()-]{6,}$');

/// A run of digits, each pair split by at most one space or hyphen.
final _digitRun = RegExp(r'\+?\d(?:[ -]?\d)*');

/// An Indian phone number inside a [_digitRun]: 10 digits, optionally led by
/// `+91`, `91` or `0`, with no digit directly before or after.
final _phone = RegExp(r'(?<!\d)(?:(?:\+91|91|0)[ -]?)?\d(?:[ -]?\d){9}(?!\d)');

/// A UPI transaction reference (UTR): exactly 12 digits.
final _utr = RegExp(r'^\d(?:[ -]?\d){11}$');

final _decimalDigit = RegExp(r'^\p{Nd}$', unicode: true);

bool _isDigit(int rune) => _decimalDigit.hasMatch(String.fromCharCode(rune));

/// [runes] with one character each: every Unicode decimal digit (such
/// as Devanagari `९`) as its ASCII digit, and any rune outside the BMP as
/// U+FFFD, so an index in it is an index into [runes].
String _ascii(List<int> runes) => String.fromCharCodes([
  for (final r in runes)
    if (r < 0x80)
      r
    else if (_isDigit(r))
      0x30 + _digitValue(r)
    else if (r > 0xFFFF)
      0xFFFD
    else
      r,
]);

/// Unicode encodes each script's digits as one or more contiguous runs of
/// 0-9, so a digit's value is its distance from the start of its run, mod 10.
int _digitValue(int rune) {
  var start = rune;
  while (_isDigit(start - 1)) {
    start--;
  }
  return (rune - start) % 10;
}

/// Whether [name] is really a phone number, as shown for someone who has
/// no label or profile name yet, in any script's digits.
bool isPhoneLike(String name) =>
    _phoneLike.hasMatch(_ascii(name.runes.toList()).trim());

/// [text] with every Indian phone number (in any script's digits)
/// replaced by `••••`. Every name and free-text field an export writes goes
/// through this; amounts and dates are built by the export itself and never
/// do. With [keepUtr], a 12-digit run is kept: in a repayment's reference it
/// is the payer's UTR, which they need to reconcile.
String redactPhones(String text, {bool keepUtr = false}) {
  final runes = text.runes.toList();
  final out = StringBuffer();
  var at = 0;
  for (final run in _digitRun.allMatches(_ascii(runes))) {
    final digits = run[0]!;
    if (keepUtr && _utr.hasMatch(digits)) continue;
    for (final phone in _phone.allMatches(digits)) {
      out
        ..write(String.fromCharCodes(runes, at, run.start + phone.start))
        ..write('••••');
      at = run.start + phone.end;
    }
  }
  return (out..write(String.fromCharCodes(runes, at))).toString();
}

/// Display names for an export by `space_members.id`. Exports leave the
/// device, so a member known only by their number becomes `Member n`
/// (their place in [members]), and a number inside a label is redacted.
Map<String, String> exportNames(List<SpaceMember> members) => {
  for (final (i, m) in members.indexed)
    m.id: isPhoneLike(m.name) || m.name.trim().isEmpty
        ? 'Member ${i + 1}'
        : redactPhones(m.name),
};
