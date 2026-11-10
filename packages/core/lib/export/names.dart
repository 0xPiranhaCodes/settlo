import 'package:settlo_core/supabase/spaces.dart';

final _phoneLike = RegExp(r'^\+?[\d\s()-]{6,}$');

/// Whether [name] is really a phone number, as shown for someone who has
/// no label or profile name yet.
bool isPhoneLike(String name) => _phoneLike.hasMatch(name.trim());

/// Display names for an export by `space_members.id`. Exports leave the
/// device, so a member known only by their number becomes `Member n`
/// (their place in [members]); numbers are never written out.
Map<String, String> exportNames(List<SpaceMember> members) => {
  for (final (i, m) in members.indexed)
    m.id: isPhoneLike(m.name) || m.name.trim().isEmpty
        ? 'Member ${i + 1}'
        : m.name,
};
