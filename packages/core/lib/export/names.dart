import 'package:settlo_core/supabase/spaces.dart';

final _phoneLike = RegExp(r'^\+?[\d\s()-]{6,}$');

/// Ten or more digits, optionally led by `+` and split by single spaces or
/// hyphens: `+91 98000 00009`, `9800000009`, `98000-00009`.
final _phoneInText = RegExp(r'\+?\d(?:[ -]?\d){9,}');

/// Whether [name] is really a phone number, as shown for someone who has
/// no label or profile name yet.
bool isPhoneLike(String name) => _phoneLike.hasMatch(name.trim());

/// [text] with every phone-like run replaced by `••••`. Every name and
/// free-text field an export writes goes through this; amounts and dates
/// are built by the export itself and never do.
String redactPhones(String text) => text.replaceAll(_phoneInText, '••••');

/// Display names for an export by `space_members.id`. Exports leave the
/// device, so a member known only by their number becomes `Member n`
/// (their place in [members]), and a number inside a label is redacted.
Map<String, String> exportNames(List<SpaceMember> members) => {
  for (final (i, m) in members.indexed)
    m.id: isPhoneLike(m.name) || m.name.trim().isEmpty
        ? 'Member ${i + 1}'
        : redactPhones(m.name),
};
