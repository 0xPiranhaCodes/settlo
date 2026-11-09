import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:settlo_core/settlo_core.dart';
import 'package:settlo_spaces/src/glyphs.dart';
import 'package:settlo_spaces/src/spaces_controller.dart';
import 'package:settlo_spaces/src/text.dart';

/// Shows [CreateSpaceSheet] with [showSettloSheet].
Future<void> showCreateSpaceSheet(BuildContext context) =>
    showSettloSheet<void>(
      context: context,
      builder: (_) => const CreateSpaceSheet(),
    );

/// New space: a name, what it is for, and people by phone number. People
/// do not need the app yet; they see the space when they verify.
///
/// The idempotency key is made once when the sheet opens and sent with
/// every attempt, so a retry after a dropped connection never makes a
/// second space.
class CreateSpaceSheet extends ConsumerStatefulWidget {
  /// The sheet.
  const new({super.key});

  @override
  ConsumerState<CreateSpaceSheet> createState() => _CreateSpaceSheetState();
}

class _CreateSpaceSheetState extends ConsumerState<CreateSpaceSheet> {
  final String _key = newIdempotencyKey();
  final _name = TextEditingController();
  final _phone = TextEditingController();
  final _person = TextEditingController();
  SpaceKind _kind = SpaceKind.flat;
  final _members = <NewSpaceMember>[];
  String? _phoneError;
  String? _error;
  bool _saving = false;

  @override
  void dispose() {
    _name.dispose();
    _phone.dispose();
    _person.dispose();
    super.dispose();
  }

  void _add() {
    final phone = toE164(_phone.text);
    // GoTrue stores the verified number without its `+`.
    final mine = ref.read(sessionProvider)?.user.phone;
    setState(() {
      if (phone == null) {
        _phoneError = 'Enter a mobile number, like 98765 43210';
      } else if (mine != null &&
          phone == toE164('+${mine.replaceFirst('+', '')}')) {
        _phoneError = "That's your number. You're in the space already.";
      } else if (_members.any((m) => m.phone == phone)) {
        _phoneError = '${groupPhone(phone)} is already added';
      } else {
        final name = _person.text.trim();
        _members.add((phone: phone, name: name.isEmpty ? phone : name));
        _phone.clear();
        _person.clear();
        _phoneError = null;
      }
    });
  }

  Future<void> _create() async {
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await ref
          .read(spacesProvider.notifier)
          .create(
            name: _name.text.trim(),
            kind: _kind,
            members: List.of(_members),
            idempotencyKey: _key,
          );
      if (mounted) Navigator.of(context).pop();
    } on IdempotencyConflict {
      ref.invalidate(spacesProvider);
      _error =
          'This space was already saved with the details you first '
          'entered. Close this to see it.';
    } on Exception {
      _error =
          "We couldn't create the space. Check your connection and try "
          'again.';
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = SettloColors.of(context);
    final text = Theme.of(context).textTheme;
    const gap = SizedBox(height: SettloSpacing.x2);
    return SingleChildScrollView(
      padding: EdgeInsets.fromLTRB(
        SettloSpacing.screenMargin,
        10,
        SettloSpacing.screenMargin,
        26 + MediaQuery.paddingOf(context).bottom,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          Center(
            child: Container(
              width: 36,
              height: 4,
              decoration: BoxDecoration(
                color: c.surfaceHighest,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Transform.translate(
                offset: const Offset(-12, 0),
                child: IconButton(
                  tooltip: 'Close',
                  onPressed: () => Navigator.of(context).pop(),
                  icon: SpacesIcon(
                    SpacesGlyph.close,
                    color: c.textPrimary,
                    size: 22,
                  ),
                ),
              ),
              Expanded(
                child: Text(
                  'New space',
                  textAlign: TextAlign.center,
                  style: text.titleSmall,
                ),
              ),
              const SizedBox(width: SettloSpacing.minTouchTarget - 12),
            ],
          ),
          const SizedBox(height: 18),
          TextField(
            controller: _name,
            textCapitalization: TextCapitalization.sentences,
            onChanged: (_) => setState(() {}),
            decoration: const InputDecoration(
              labelText: 'Name',
              hintText: 'Flat 402',
            ),
          ),
          gap,
          SSegmentedControl<SpaceKind>(
            segments: const [
              (value: SpaceKind.flat, label: 'Flat'),
              (value: SpaceKind.trip, label: 'Trip'),
              (value: SpaceKind.friend, label: 'Friend'),
              (value: SpaceKind.other, label: 'Other'),
            ],
            selected: _kind,
            onChanged: (kind) => setState(() => _kind = kind),
          ),
          const SizedBox(height: SettloSpacing.x3),
          Text('PEOPLE', style: sectionLabel(c)),
          const SizedBox(height: SettloSpacing.x1),
          for (final m in _members)
            MergeSemantics(
              child: Row(
                children: [
                  SAvatar(m.name, size: 36),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          m.name,
                          style: SettloTypography.figtree(
                            14,
                            color: c.textPrimary,
                          ),
                        ),
                        if (m.name != m.phone)
                          Text(
                            groupPhone(m.phone),
                            style: SettloTypography.figtree(
                              12,
                              color: c.textSecondary,
                            ),
                          ),
                      ],
                    ),
                  ),
                  IconButton(
                    tooltip: 'Remove ${m.name}',
                    onPressed: () => setState(() => _members.remove(m)),
                    icon: SpacesIcon(
                      SpacesGlyph.close,
                      color: c.textSecondary,
                      size: 18,
                    ),
                  ),
                ],
              ),
            ),
          Text(
            "They don't need the app yet. They see the space when they "
            'verify their number.',
            style: SettloTypography.figtree(13, color: c.textSecondary),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _phone,
            keyboardType: TextInputType.phone,
            autofillHints: const [AutofillHints.telephoneNumber],
            onSubmitted: (_) => _add(),
            decoration: InputDecoration(
              labelText: 'Phone number',
              hintText: '98765 43210',
              errorText: _phoneError,
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _person,
            textCapitalization: TextCapitalization.words,
            onSubmitted: (_) => _add(),
            decoration: const InputDecoration(labelText: 'Their name'),
          ),
          const SizedBox(height: 12),
          SSecondaryButton(
            label: 'Add person',
            icon: SpacesIcon(SpacesGlyph.plus, color: c.textPrimary, size: 18),
            onPressed: _add,
          ),
          if (_error case final error?) ...[
            gap,
            Text(
              error,
              style: SettloTypography.figtree(13, color: c.textPrimary),
            ),
          ],
          const SizedBox(height: SettloSpacing.x3),
          SPrimaryButton(
            label: _saving ? 'Creating…' : 'Create space',
            onPressed: _saving || _name.text.trim().isEmpty ? null : _create,
          ),
        ],
      ),
    );
  }
}
