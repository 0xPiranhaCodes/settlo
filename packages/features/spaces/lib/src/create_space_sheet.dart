import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:settlo_core/settlo_core.dart';
import 'package:settlo_spaces/src/glyphs.dart';
import 'package:settlo_spaces/src/spaces_controller.dart';
import 'package:settlo_spaces/src/text.dart';

/// Shows [CreateSpaceSheet], for [space]'s members when given: a page
/// sheet at the root, or a nested step inside the current sheet.
Future<void> showCreateSpaceSheet(
  BuildContext context, {
  SpaceSummary? space,
}) => pushSettloSheet<void>(context, (_) => CreateSpaceSheet(space: space));

/// New space: a name, what it is for, and people by phone number. People
/// do not need the app yet; they see the space when they verify. Given a
/// [space], it is that space's Members: who is in it, and the same step
/// to add more.
///
/// The idempotency key is made once when the sheet opens and sent with
/// every attempt, so a retry after a dropped connection never makes a
/// second space.
class CreateSpaceSheet extends ConsumerStatefulWidget {
  /// The sheet; adds people to [space] when given.
  const new({this.space, super.key});

  /// The existing space whose members are shown, or null for a new one.
  final SpaceSummary? space;

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
      } else if (widget.space?.members.any((m) => m.phone == phone) ?? false) {
        _phoneError = '${groupPhone(phone)} is already in the space';
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
    final controller = ref.read(spacesProvider.notifier);
    try {
      if (widget.space case final space?) {
        await controller.addMembers(
          space.id,
          List.of(_members),
          idempotencyKey: _key,
        );
      } else {
        await controller.create(
          name: _name.text.trim(),
          kind: _kind,
          members: List.of(_members),
          idempotencyKey: _key,
        );
      }
      if (mounted) finishSettloSheet(context);
    } on IdempotencyConflict {
      ref.invalidate(spacesProvider);
      _error = widget.space == null
          ? 'This space was already saved with the details you first '
                'entered. Close this to see it.'
          : 'The people you first added were already saved. Close this to '
                'see them.';
    } on SessionEnded {
      // Signed out mid-tap: the user has left, so there is nothing to say.
    } on Exception {
      _error = widget.space == null
          ? "We couldn't create the space. Check your connection and try "
                'again.'
          : "We couldn't add them. Check your connection and try again.";
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  /// Input the user would lose by closing.
  bool get _dirty =>
      _kind != SpaceKind.flat ||
      _members.isNotEmpty ||
      [_name, _phone, _person].any((c) => c.text.isNotEmpty);

  /// iOS: a drag down or ✕ asks before discarding input.
  Future<void> _confirmClose() async {
    if (_saving) return;
    final discard = await showSettloActionSheet(
      context: context,
      title: 'Discard changes?',
      destructive: 'Discard',
      cancel: 'Keep editing',
    );
    if (discard == true && mounted) finishSettloSheet(context);
  }

  @override
  Widget build(BuildContext context) {
    final c = SettloColors.of(context);
    final ios = Theme.of(context).platform == TargetPlatform.iOS;
    final space = widget.space;
    final canCreate =
        !_saving &&
        (space == null ? _name.text.trim().isNotEmpty : _members.isNotEmpty);
    const gap = SizedBox(height: SettloSpacing.x2);
    Widget person(String name, {String? detail, VoidCallback? onRemove}) =>
        MergeSemantics(
          child: ConstrainedBox(
            constraints: const BoxConstraints(
              minHeight: SettloSpacing.minTouchTarget,
            ),
            child: Row(
              children: [
                SAvatar(name, size: 36),
                const SizedBox(width: SettloSpacing.x2),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        name,
                        style: SettloTypography.body(color: c.textPrimary),
                      ),
                      if (detail != null)
                        Text(
                          detail,
                          style: SettloTypography.footnote(
                            color: c.textSecondary,
                          ),
                        ),
                    ],
                  ),
                ),
                if (onRemove != null)
                  IconButton(
                    tooltip: 'Remove $name',
                    onPressed: onRemove,
                    icon: SpacesIcon(
                      SpacesGlyph.close,
                      color: c.textSecondary,
                      size: 18,
                    ),
                  ),
              ],
            ),
          ),
        );
    final form = SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(
        16,
        SettloSpacing.x1,
        16,
        SettloSpacing.x3,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          if (space == null) ...[
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
          ],
          Text('PEOPLE', style: sectionLabel(c)),
          const SizedBox(height: SettloSpacing.x1),
          for (final m in [...?space?.members])
            person(
              m.isYou ? 'You' : m.name,
              detail: m.joined
                  ? null
                  : "${maskPhone(m.phone)} · hasn't joined yet",
            ),
          for (final m in _members)
            person(
              m.name,
              detail: m.name == m.phone ? null : groupPhone(m.phone),
              onRemove: () => setState(() => _members.remove(m)),
            ),
          Text(
            "They don't need the app yet. They see the space when they "
            'verify their number.',
            style: SettloTypography.subheadline(color: c.textSecondary),
          ),
          const SizedBox(height: SettloSpacing.x2),
          TextField(
            controller: _phone,
            keyboardType: TextInputType.phone,
            autofillHints: const [AutofillHints.telephoneNumber],
            onChanged: (_) => setState(() {}),
            onSubmitted: (_) => _add(),
            decoration: InputDecoration(
              labelText: 'Phone number',
              hintText: '98765 43210',
              errorText: _phoneError,
            ),
          ),
          const SizedBox(height: SettloSpacing.x2),
          TextField(
            controller: _person,
            textCapitalization: TextCapitalization.words,
            onChanged: (_) => setState(() {}),
            onSubmitted: (_) => _add(),
            decoration: const InputDecoration(labelText: 'Their name'),
          ),
          const SizedBox(height: SettloSpacing.x2),
          SSecondaryButton(
            label: 'Add person',
            icon: SpacesIcon(SpacesGlyph.plus, color: c.textPrimary, size: 18),
            onPressed: _add,
          ),
          if (_error case final error?) ...[
            gap,
            Text(error, style: SettloTypography.subheadline(color: c.error)),
          ],
        ],
      ),
    );
    final n = _members.length;
    // Shared sheet chrome and form, with the primary action pinned below.
    final sheet = Material(
      type: MaterialType.transparency,
      child: Column(
        children: [
          SSheetHeader(
            title: space == null ? 'New space' : 'Members',
            onClose: () {
              if (ios && (_dirty || _saving)) {
                unawaited(_confirmClose());
              } else {
                finishSettloSheet(context);
              }
            },
          ),
          const SizedBox(height: 16),
          Expanded(child: form),
          Container(
            width: double.infinity,
            padding: EdgeInsets.fromLTRB(
              16,
              0,
              16,
              SettloSpacing.x2 +
                  MediaQuery.paddingOf(context).bottom +
                  // The Material sheet already sits above the keyboard.
                  (ios ? MediaQuery.viewInsetsOf(context).bottom : 0),
            ),
            child: SPrimaryButton(
              label: switch ((space, _saving)) {
                (null, true) => 'Creating…',
                (null, false) => 'Create space',
                (_, true) => 'Adding…',
                _ when n == 0 => 'Add people',
                _ => n == 1 ? 'Add ${_members.single.name}' : 'Add $n people',
              },
              onPressed: canCreate ? _create : null,
            ),
          ),
        ],
      ),
    );
    if (!ios) return sheet;
    return PopScope(
      canPop: !_saving && !_dirty,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) unawaited(_confirmClose());
      },
      child: sheet,
    );
  }
}
