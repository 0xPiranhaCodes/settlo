import 'package:flutter/widgets.dart';
import 'package:settlo_core/settlo_core.dart';

/// A number that has not joined, as the canvas masks it: `+91 ••• 2210`,
/// with no-break spaces so it never wraps.
String maskPhone(String e164) {
  final last = e164.substring(e164.length - 4);
  return e164.startsWith('+91') ? '+91\u00A0•••\u00A0$last' : '•••\u00A0$last';
}

/// `Rahul`, `Rahul and Priya`, `Rahul, Priya and Dev`.
String joinNames(List<String> names) => switch (names) {
  [] => '',
  [final one] => one,
  [...final rest, final last] => '${rest.join(', ')} and $last',
};

/// Small-caps section labels: 12, tracked, secondary.
TextStyle sectionLabel(SettloColors c) =>
    SettloTypography.figtree(12, letterSpacing: 0.3, color: c.textSecondary);

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
