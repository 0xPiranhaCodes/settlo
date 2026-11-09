import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// A country a phone number can be in: its ISO code, dialling code and how
/// many national digits a mobile number there has.
@immutable
final class Country {
  /// A country [name] with [iso] code and [dialCode] (digits, no `+`).
  const new({
    required this.iso,
    required this.dialCode,
    required this.name,
    this.minDigits = 6,
    this.maxDigits = 12,
  });

  /// India, preselected: the audience is Indian (canvas note n01).
  static const india = Country(
    iso: 'IN',
    dialCode: '91',
    name: 'India',
    minDigits: 10,
    maxDigits: 10,
  );

  /// The picker's choices: India first, then where most NRIs live.
  static const List<Country> all = [
    india,
    Country(iso: 'AE', dialCode: '971', name: 'United Arab Emirates'),
    Country(iso: 'US', dialCode: '1', name: 'United States'),
    Country(iso: 'GB', dialCode: '44', name: 'United Kingdom'),
    Country(iso: 'CA', dialCode: '1', name: 'Canada'),
    Country(iso: 'SA', dialCode: '966', name: 'Saudi Arabia'),
    Country(iso: 'SG', dialCode: '65', name: 'Singapore'),
    Country(iso: 'AU', dialCode: '61', name: 'Australia'),
    Country(iso: 'QA', dialCode: '974', name: 'Qatar'),
    Country(iso: 'KW', dialCode: '965', name: 'Kuwait'),
    Country(iso: 'OM', dialCode: '968', name: 'Oman'),
    Country(iso: 'NZ', dialCode: '64', name: 'New Zealand'),
    Country(iso: 'DE', dialCode: '49', name: 'Germany'),
    Country(iso: 'MY', dialCode: '60', name: 'Malaysia'),
  ];

  /// ISO 3166 alpha-2 code, shown instead of a flag.
  final String iso;

  /// Dialling code, digits only.
  final String dialCode;

  /// English name.
  final String name;

  /// Fewest national digits a mobile number can have.
  final int minDigits;

  /// Most national digits a mobile number can have.
  final int maxDigits;

  /// The chip text, such as `IN +91`.
  String get label => '$iso +$dialCode';

  /// The national digits in [input], without spaces, a trunk `0` or this
  /// country's code typed or pasted in front.
  String nationalDigits(String input) {
    var digits = input.replaceAll(RegExp(r'\D'), '');
    final prefixed =
        input.trimLeft().startsWith('+') || digits.length > maxDigits;
    if (prefixed && digits.startsWith(dialCode)) {
      digits = digits.substring(dialCode.length);
    }
    return digits.replaceFirst(RegExp('^0+'), '');
  }

  /// The number in E.164 (`+919876543210`), or null when [national] cannot
  /// be a mobile number here.
  String? e164(String national) {
    final digits = nationalDigits(national);
    final valid = this == india
        ? RegExp(r'^[6-9]\d{9}$').hasMatch(digits)
        : digits.length >= minDigits &&
              digits.length <= maxDigits &&
              dialCode.length + digits.length <= 15;
    return valid ? '+$dialCode$digits' : null;
  }

  /// [digits] grouped for reading: `98765 43210` in India, unchanged
  /// elsewhere.
  String group(String digits) => this == india && digits.length > 5
      ? '${digits.substring(0, 5)} ${digits.substring(5)}'
      : digits;

  /// [phone] (E.164 in this country) as people read it, such as
  /// `+91 98765 43210`.
  String display(String phone) =>
      '+$dialCode ${group(phone.substring(dialCode.length + 1))}';
}

/// Keeps a phone field to this country's national digits, grouped for
/// reading. A pasted `+91 98765 43210` or `098765 43210` becomes
/// `98765 43210`.
final class NationalNumberFormatter extends TextInputFormatter {
  /// A formatter for numbers in [country].
  new(this.country);

  /// The selected country.
  final Country country;

  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    var digits = country.nationalDigits(newValue.text);
    if (digits.length > country.maxDigits) {
      digits = digits.substring(0, country.maxDigits);
    }
    final text = country.group(digits);
    return TextEditingValue(
      text: text,
      selection: TextSelection.collapsed(offset: text.length),
    );
  }
}
