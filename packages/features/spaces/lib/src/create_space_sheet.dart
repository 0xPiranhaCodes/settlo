import 'dart:async';

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:settlo_core/settlo_core.dart';
import 'package:settlo_spaces/src/glyphs.dart';
import 'package:settlo_spaces/src/spaces_controller.dart';
import 'package:settlo_spaces/src/text.dart';

/// Shows [CreateSpaceSheet]: a page sheet on iOS, [showSettloSheet]
/// elsewhere.
Future<void> showCreateSpaceSheet(BuildContext context) =>
    showSettloPageSheet<void>(
      context: context,
      builder: (_) => const CreateSpaceSheet(),
      fallback: () => showSettloSheet<void>(
        context: context,
        builder: (_) => const CreateSpaceSheet(),
      ),
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
    } on SessionEnded {
      // Signed out mid-tap: the user has left, so there is nothing to say.
    } on Exception {
      _error =
          "We couldn't create the space. Check your connection and try "
          'again.';
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  /// Input the user would lose by closing.
  bool get _dirty =>
      _kind != SpaceKind.flat ||
      _members.isNotEmpty ||
      [_name, _phone, _person].any((c) => c.text.isNotEmpty);

  /// iOS: a drag down or Cancel asks before discarding input.
  Future<void> _confirmClose() async {
    if (_saving) return;
    final discard = await showSettloActionSheet(
      context: context,
      title: 'Discard changes?',
      destructive: 'Discard',
      cancel: 'Keep editing',
    );
    if (discard == true && mounted) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final c = SettloColors.of(context);
    final text = Theme.of(context).textTheme;
    final ios = Theme.of(context).platform == TargetPlatform.iOS;
    final canCreate = !_saving && _name.text.trim().isNotEmpty;
    const gap = SizedBox(height: SettloSpacing.x2);
    final form = SingleChildScrollView(
      padding: EdgeInsets.fromLTRB(
        SettloSpacing.screenMargin,
        10,
        SettloSpacing.screenMargin,
        26 +
            MediaQuery.paddingOf(context).bottom +
            // The Material sheet already sits above the keyboard.
            (ios ? MediaQuery.viewInsetsOf(context).bottom : 0),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          if (!ios)
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
          const SizedBox(height: SettloSpacing.x3),
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
                  const SizedBox(width: SettloSpacing.x2),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          m.name,
                          style: SettloTypography.body(color: c.textPrimary),
                        ),
                        if (m.name != m.phone)
                          Text(
                            groupPhone(m.phone),
                            style: SettloTypography.footnote(
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
            Text(
              error,
              style: SettloTypography.subheadline(color: c.textPrimary),
            ),
          ],
          if (!ios) ...[
            const SizedBox(height: SettloSpacing.x3),
            SPrimaryButton(
              label: _saving ? 'Creating…' : 'Create space',
              onPressed: canCreate ? _create : null,
            ),
          ],
        ],
      ),
    );
    if (!ios) return form;
    // A page sheet as in Apple's create sheets: Cancel leading, the
    // confirming Create trailing in the action colour.
    final bar = SettloTypography.body(color: c.textPrimary);
    return PopScope(
      canPop: !_saving && !_dirty,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) unawaited(_confirmClose());
      },
      child: Material(
        type: MaterialType.transparency,
        child: Column(
          children: [
            CupertinoNavigationBar(
              automaticallyImplyLeading: false,
              transitionBetweenRoutes: false,
              backgroundColor: c.surface,
              border: null,
              leading: CupertinoButton(
                padding: EdgeInsets.zero,
                onPressed: () => Navigator.of(context).maybePop(),
                child: Text('Cancel', style: bar),
              ),
              middle: Text(
                'New space',
                style: SettloTypography.headline(color: c.textPrimary),
              ),
              trailing: CupertinoButton(
                padding: EdgeInsets.zero,
                onPressed: canCreate ? _create : null,
                child: Text(
                  _saving ? 'Creating…' : 'Create',
                  style: SettloTypography.body(
                    weight: FontWeight.w600,
                    color: canCreate ? c.action : c.textMuted,
                  ),
                ),
              ),
            ),
            Expanded(child: form),
          ],
        ),
      ),
    );
  }
}
