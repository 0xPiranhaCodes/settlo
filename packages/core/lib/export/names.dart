import 'package:settlo_core/supabase/spaces.dart';

final _phoneLike = RegExp(r'^\(?\+?[\d\s().-]{6,}$');

/// What may sit between a phone's digits once [_normalise]d: up to two
/// spaces, dashes, dots or parentheses, as in `(+91) 98000.00009`.
const _sep = r'[ .()\-]{0,2}';

/// An Indian phone number: 10 digits, optionally led by `+91`, `91` or `0`
/// (itself optionally in parentheses), with no digit directly before or
/// after.
final _phone = RegExp(
  '(?<!\\d)\\(?(?:(?:\\+91|91|0)$_sep)?\\d(?:$_sep\\d){9}(?!\\d)',
);

/// A UPI transaction reference (UTR): exactly 12 contiguous digits.
final _utr = RegExp(r'^\d{12}$');

final _decimalDigit = RegExp(r'^\p{Nd}$', unicode: true);
final _invisible = RegExp(r'^\p{Cf}$', unicode: true);
final _space = RegExp(r'^\p{Zs}$', unicode: true);
final _dash = RegExp(r'^\p{Pd}$', unicode: true);

bool _isDigit(int rune) => _decimalDigit.hasMatch(String.fromCharCode(rune));

/// [runes] for matching, one character per kept rune, with `at[i]` the index
/// in [runes] of character `i`. Every Unicode decimal digit (such as
/// Devanagari `९`) becomes its ASCII digit, every space (such as a
/// no-break space) a space, and every dash a hyphen. Invisible format
/// characters (zero-width spaces and joiners, bidi marks) are dropped, so
/// they cannot split a number; with [keepInvisible] they stay, as a
/// non-digit, so a UTR check sees them. Runes outside the BMP become
/// U+FFFD, so each is one character.
({String text, List<int> at}) _normalise(
  List<int> runes, {
  bool keepInvisible = false,
}) {
  final chars = <int>[];
  final at = <int>[];
  for (final (i, r) in runes.indexed) {
    final c = r < 0x80 ? r : _unicode(r, keepInvisible: keepInvisible);
    if (c == null) continue;
    chars.add(c);
    at.add(i);
  }
  return (text: String.fromCharCodes(chars), at: at);
}

int? _unicode(int rune, {required bool keepInvisible}) {
  final char = String.fromCharCode(rune);
  if (_invisible.hasMatch(char)) return keepInvisible ? 0xFFFD : null;
  if (_isDigit(rune)) return 0x30 + _digitValue(rune);
  if (_space.hasMatch(char)) return 0x20;
  if (_dash.hasMatch(char)) return 0x2D;
  return rune > 0xFFFF ? 0xFFFD : rune;
}

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
/// no label or profile name yet, in any script's digits and separators.
bool isPhoneLike(String name) =>
    _phoneLike.hasMatch(_normalise(name.runes.toList()).text.trim());

/// [text] with every Indian phone number (in any script's digits, split by
/// any spaces, dashes, dots, parentheses or invisible characters) replaced
/// by `••••`. Every name and free-text field an export writes goes through
/// this; amounts and dates are built by the export itself and never do.
/// With [keepUtr], a [text] that is nothing but 12 contiguous digits (after
/// trimming) is kept: as a repayment's whole reference it is the payer's
/// UTR, which they need to reconcile. Anything else around or between the
/// digits, even an invisible character, and the usual rules apply.
String redactPhones(String text, {bool keepUtr = false}) {
  // shortcut: lookalike digits and marks aren't folded here; the server does.
  final runes = text.runes.toList();
  if (keepUtr &&
      _utr.hasMatch(_normalise(runes, keepInvisible: true).text.trim())) {
    return text;
  }
  final (text: normal, :at) = _normalise(runes);
  final out = StringBuffer();
  var next = 0;
  for (final phone in _phone.allMatches(normal)) {
    out
      ..write(String.fromCharCodes(runes, next, at[phone.start]))
      ..write('••••');
    next = at[phone.end - 1] + 1;
  }
  return (out..write(String.fromCharCodes(runes, next))).toString();
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
