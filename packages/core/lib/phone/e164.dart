/// An Indian mobile number grouped as on the canvas, `+91 98765 43210`.
String groupPhone(String e164) => e164.startsWith('+91') && e164.length == 13
    ? '+91 ${e164.substring(3, 8)} ${e164.substring(8)}'
    : e164;

/// [input] as E.164, or null when it is not a phone number. A bare
/// ten-digit Indian mobile number (optionally with a leading 0) gets +91.
String? toE164(String input) {
  var s = input.replaceAll(RegExp(r'[\s\-().]'), '');
  if (RegExp(r'^0?[6-9]\d{9}$').hasMatch(s)) {
    s = '+91${s.substring(s.length - 10)}';
  }
  return RegExp(r'^\+[1-9]\d{7,14}$').hasMatch(s) ? s : null;
}
