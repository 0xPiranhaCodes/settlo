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
    SettloTypography.footnote(letterSpacing: 0.3, color: c.textSecondary);
