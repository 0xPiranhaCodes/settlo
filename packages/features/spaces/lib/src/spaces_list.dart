import 'dart:math' as math;

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:settlo_core/settlo_core.dart';
import 'package:settlo_platform/settlo_platform.dart';
import 'package:settlo_spaces/src/create_space_sheet.dart';
import 'package:settlo_spaces/src/glyphs.dart';
import 'package:settlo_spaces/src/spaces_controller.dart';
import 'package:settlo_spaces/src/text.dart';

/// The Spaces tab (SpacesList artboard).
///
/// Each card is a mini balance sheet: your balance, and for a space with
/// spending this month a stacked bar of who paid what share (canvas note
/// n10). Members who have not joined are listed under the cards, because
/// they are the main cause of stale balances.
class SpacesListScreen extends ConsumerStatefulWidget {
  /// The Spaces tab.
  const new({super.key});

  @override
  ConsumerState<SpacesListScreen> createState() => _SpacesListScreenState();
}

class _SpacesListScreenState extends ConsumerState<SpacesListScreen> {
  /// The chosen filter chip; null is All.
  SpaceKind? _filter;

  /// iOS search by name; empty shows every space.
  String _query = '';

  @override
  Widget build(BuildContext context) {
    final spaces = ref.watch(spacesProvider);
    final all = spaces.value;
    final shown = [
      for (final s in all ?? const <SpaceSummary>[])
        if ((_filter == null || s.kind == _filter) &&
            searchMatches(_query, s.name))
          s,
    ];
    final pending = [
      for (final s in shown)
        for (final m in s.others)
          if (!m.joined) (s, m),
    ];
    final c = SettloColors.of(context);
    final media = MediaQuery.of(context);
    final ios = Theme.of(context).platform == TargetPlatform.iOS;
    return Scaffold(
      body: DefaultTextStyle.merge(
        style: const TextStyle(letterSpacing: 0, height: 1.2),
        child: SettloScrollScaffold(
          title: 'Spaces',
          stickyHeader: false,
          onRefresh: () => ref.refresh(spacesProvider.future),
          padding: EdgeInsets.fromLTRB(
            SettloSpacing.screenMargin,
            math.max(media.padding.top, 44) + 16,
            SettloSpacing.screenMargin,
            media.padding.bottom + SettloSpacing.x2,
          ),
          children: [
            SettloNavigationHeader(
              title: 'Spaces',
              // iOS: a plain bar button, as in Apple's lists; glass on 26.
              trailing: SettloTabActions(
                onBell: () => context.go(SettloRoutes.activity),
                leading: GlassAction(
                  label: 'New space',
                  symbol: 'plus',
                  onPressed: () => showCreateSpaceSheet(context),
                  fallback: ios
                      ? Semantics(
                          label: 'New space',
                          button: true,
                          excludeSemantics: true,
                          onTap: () => showCreateSpaceSheet(context),
                          child: CupertinoButton(
                            padding: EdgeInsets.zero,
                            minimumSize: const Size.square(
                              SettloSpacing.minTouchTarget,
                            ),
                            onPressed: () => showCreateSpaceSheet(context),
                            child: Icon(
                              CupertinoIcons.add,
                              color: c.textPrimary,
                              size: 28,
                            ),
                          ),
                        )
                      : IconButton(
                          tooltip: 'New space',
                          onPressed: () => showCreateSpaceSheet(context),
                          style: IconButton.styleFrom(
                            fixedSize: const Size.square(
                              SettloSpacing.minTouchTarget,
                            ),
                            minimumSize: Size.zero,
                            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                            backgroundColor: c.surface,
                            side: BorderSide(color: c.hairline),
                          ),
                          icon: SpacesIcon(
                            SpacesGlyph.plus,
                            color: c.textPrimary,
                            size: 22,
                          ),
                        ),
                ),
              ),
            ),
            if (ios) ...[
              const SizedBox(height: SettloSpacing.x1),
              SSearchField(onChanged: (q) => setState(() => _query = q)),
              const SizedBox(height: SettloSpacing.x1),
            ] else
              // Chips are 36 drawn inside a 44 target: 4 less above and
              // below keeps the canvas's 24 and 18.
              const SizedBox(height: SettloSpacing.x3),
            Row(
              children: [
                for (final (kind, label) in const [
                  (null, 'All'),
                  (SpaceKind.flat, 'Home'),
                  (SpaceKind.trip, 'Trips'),
                ]) ...[
                  SChip(
                    label: label,
                    selected: _filter == kind,
                    onSelected: (_) => setState(() => _filter = kind),
                  ),
                  const SizedBox(width: SettloSpacing.x1),
                ],
              ],
            ),
            const SizedBox(height: SettloSpacing.x2),
            if (all == null)
              Text(
                spaces.hasError
                    ? "We couldn't load your spaces. Pull down to try again."
                    : '',
                style: SettloTypography.subheadline(color: c.textSecondary),
              )
            else if (all.isEmpty)
              const _NoSpaces()
            else if (shown.isEmpty && _query.isNotEmpty)
              Text(
                'No space matches "$_query".',
                style: SettloTypography.subheadline(color: c.textSecondary),
              )
            else
              for (final (i, s) in shown.indexed) ...[
                if (i > 0) const SizedBox(height: SettloSpacing.x2),
                _SpaceCard(s),
              ],
            if (pending.isNotEmpty) ...[
              const SizedBox(height: SettloSpacing.x3),
              Text('INVITE PENDING', style: sectionLabel(c)),
              const SizedBox(height: SettloSpacing.x2),
              for (final (i, (space, member)) in pending.indexed) ...[
                if (i > 0) const SizedBox(height: SettloSpacing.x1),
                _PendingCard(space: space, member: member),
              ],
            ],
          ],
        ),
      ),
    );
  }
}

class _NoSpaces extends StatelessWidget {
  const new();

  @override
  Widget build(BuildContext context) {
    final c = SettloColors.of(context);
    return SCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            'Flatmates, a trip, or one friend. Add people by phone number '
            "— they don't need the app yet.",
            style: SettloTypography.subheadline(color: c.textSecondary)
                .copyWith(height: 1.5),
          ),
          const SizedBox(height: SettloSpacing.x3),
          SPrimaryButton(
            label: 'Start a space',
            onPressed: () => showCreateSpaceSheet(context),
          ),
        ],
      ),
    );
  }
}

class _SpaceCard extends StatelessWidget {
  const new(this.space);

  final SpaceSummary space;

  @override
  Widget build(BuildContext context) {
    final c = SettloColors.of(context);
    final s = space;
    final others = s.others;
    final small = SettloTypography.caption1(color: c.textSecondary);
    final total = s.monthTotal.value;
    int percent(Paise part) => (part.value * 100 / total).round();
    return MergeSemantics(
      child: SPressable(
        ringRadius: BorderRadius.circular(SettloRadius.card),
        onTap: () => context.go(SettloRoutes.space(s.id)),
        child: SCard(
          padding: const EdgeInsets.all(SettloSpacing.screenMargin),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              SResponsiveRow(
                children: [
                  SpaceKindTile(s.kind),
                  const SizedBox(width: SettloSpacing.x2),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          s.name,
                          maxLines:
                              MediaQuery.textScalerOf(context).scale(1) >= 1.5
                              ? null
                              : 1,
                          overflow: TextOverflow.ellipsis,
                          style: SettloTypography.callout(color: c.textPrimary),
                        ),
                        const SizedBox(height: 3),
                        Text(
                          switch (others) {
                            [] => 'Just you',
                            [_] when s.kind == SpaceKind.friend => '1:1',
                            [_] ||
                            [_, _] => others.map((m) => m.name).join(', '),
                            _ => '${others.length + 1} people',
                          },
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: SettloTypography.footnote(
                            color: c.textSecondary,
                          ).copyWith(height: 1.3),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: SettloSpacing.x1),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      MoneyText(
                        s.balance,
                        signed: true,
                        size: 16,
                        tone: switch (s.balance.value) {
                          > 0 => MoneyTone.owedToYou,
                          < 0 => MoneyTone.youOwe,
                          _ => MoneyTone.settled,
                        },
                      ),
                      Text(switch (s.balance.value) {
                        > 0 => 'owed to you',
                        < 0 => 'you owe',
                        _ when !s.hasExpenses => 'nothing yet',
                        _ => 'settled',
                      }, style: small),
                    ],
                  ),
                ],
              ),
              if (total > 0 &&
                  (others.isNotEmpty || s.departed.isNotEmpty)) ...[
                const SizedBox(height: 16),
                _PaidBar(s),
                const SizedBox(height: SettloSpacing.x1),
                SResponsiveRow(
                  children: [
                    Expanded(
                      child: Text(
                        'You paid ${percent(s.you.monthPaid)}% of '
                        '${formatInr(s.monthTotal)}',
                        semanticsLabel:
                            'You paid ${percent(s.you.monthPaid)}% of '
                            '${spokenInr(s.monthTotal)}',
                        style: small,
                      ),
                    ),
                    Text(
                      'fair share ${percent(s.yourFairShare)}%',
                      style: small,
                    ),
                  ],
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

/// Who paid what share of this month's spending: you first in primary
/// text, then everyone else in the order they were added, then members
/// who have left since.
class _PaidBar extends StatelessWidget {
  const new(this.space);

  final SpaceSummary space;

  @override
  Widget build(BuildContext context) {
    final c = SettloColors.of(context);
    final payers = [
      for (final m in [space.you, ...space.others, ...space.departed])
        if (m.monthPaid.value > 0) m,
    ];
    return ExcludeSemantics(
      child: Row(
        children: [
          for (final (i, m) in payers.indexed) ...[
            if (i > 0) const SizedBox(width: SettloSpacing.x1),
            Expanded(
              flex: m.monthPaid.value,
              child: Container(
                height: 6,
                decoration: BoxDecoration(
                  color: m.isYou ? c.brandAccent : c.surfaceHighest,
                  borderRadius: BorderRadius.circular(3),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _PendingCard extends ConsumerStatefulWidget {
  const new({required this.space, required this.member});

  final SpaceSummary space;
  final SpaceMember member;

  @override
  ConsumerState<_PendingCard> createState() => _PendingCardState();
}

class _PendingCardState extends ConsumerState<_PendingCard> {
  String _inviteKey = newIdempotencyKey();
  bool _busy = false;

  Future<void> _send() async {
    if (_busy) return;
    setState(() => _busy = true);
    final member = widget.member;
    try {
      final token = await ref
          .read(invitesRepositoryProvider)
          .issueSpace(member.id, idempotencyKey: _inviteKey);
      // A successful issue is complete: the next share creates another live
      // link. Only an ambiguous/failed issue retries the same key.
      _inviteKey = newIdempotencyKey();
      final opened = await ref.read(openUrlProvider)(
        Uri.https('wa.me', '/${member.phone.substring(1)}', {
          'text': spaceInviteText(
            widget.space.you.name,
            widget.space.name,
            inviteLink(token),
          ),
        }),
      );
      if (!opened && mounted) {
        showSettloNotice(context, "Couldn't open WhatsApp");
      }
    } on Exception {
      if (mounted) {
        showSettloNotice(context, "Couldn't create the invite");
      }
    }
    if (mounted) setState(() => _busy = false);
  }

  /// Says who is waiting and offers the invite, so a tap never leaves the
  /// app unannounced.
  Future<void> _ask(String detail) async {
    final c = SettloColors.of(context);
    final member = widget.member;
    final send = await pushSettloSheet<bool>(
      context,
      (sheet) => SSheetScaffold(
        title: 'Resend invite',
        onClose: () => finishSettloSheet(sheet),
        children: [
          Text(
            "${member.name} hasn't joined yet",
            style: SettloTypography.title3(color: c.textPrimary),
          ),
          const SizedBox(height: 8),
          Text(
            '$detail. They see the space once they open the link and '
            'verify their number.',
            style: SettloTypography.body(color: c.textSecondary),
          ),
          const SizedBox(height: 24),
          SPrimaryButton(
            label: 'Resend invite on WhatsApp',
            onPressed: () => finishSettloSheet(sheet, true),
          ),
        ],
      ),
    );
    if (send ?? false) await _send();
  }

  @override
  Widget build(BuildContext context) {
    final c = SettloColors.of(context);
    final space = widget.space;
    final member = widget.member;
    final b = member.balance;
    final number = maskPhone(member.phone);
    String detail(String amount) => b.value == 0
        ? 'Added to ${space.name} as $number'
        : '$amount in ${space.name} is recorded against $number';
    return SPressable(
      label:
          "${member.name} hasn't joined yet. "
          '${detail(spokenInr(Paise(b.value.abs())))}',
      ringRadius: BorderRadius.circular(SettloRadius.card),
      onTap: _busy ? null : () => _ask(detail(formatInr(Paise(b.value.abs())))),
      child: SCard(
        child: Row(
          children: [
            SAvatar(member.name, size: 36),
            const SizedBox(width: SettloSpacing.x2),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    "${member.name} hasn't joined yet",
                    style: SettloTypography.body(color: c.textPrimary),
                  ),
                  Row(
                    children: [
                      Icon(Icons.schedule, size: 14, color: c.pending),
                      const SizedBox(width: 4),
                      Expanded(
                        child: Text(
                          detail(formatInr(Paise(b.value.abs()))),
                          semanticsLabel: detail(
                            spokenInr(Paise(b.value.abs())),
                          ),
                          style: SettloTypography.footnote(color: c.pending)
                              .copyWith(height: 1.3),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Fixed trust copy for a space capability; never includes balances.
String spaceInviteText(String inviter, String space, Uri link) =>
    'Hi, this is $inviter. I added you to $space on SabkiJeb. Nothing is '
    'shown until you verify this number. $link';
