import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:settlo_core/settlo_core.dart';
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

  @override
  Widget build(BuildContext context) {
    final spaces = ref.watch(spacesProvider);
    final all = spaces.value;
    final shown = [
      for (final s in all ?? const <SpaceSummary>[])
        if (_filter == null || s.kind == _filter) s,
    ];
    final pending = [
      for (final s in shown)
        for (final m in s.others)
          if (!m.joined) (s, m),
    ];
    final c = SettloColors.of(context);
    final media = MediaQuery.of(context);
    return Scaffold(
      body: DefaultTextStyle.merge(
        style: const TextStyle(letterSpacing: 0, height: 1.2),
        child: RefreshIndicator(
          onRefresh: () => ref.refresh(spacesProvider.future),
          child: ListView(
            padding: EdgeInsets.fromLTRB(
              SettloSpacing.screenMargin,
              math.max(media.padding.top, 44) + 16,
              SettloSpacing.screenMargin,
              media.padding.bottom + SettloSpacing.x2,
            ),
            children: [
              Row(
                children: [
                  Text(
                    'Spaces',
                    style: SettloTypography.figtree(
                      24,
                      weight: FontWeight.w500,
                      letterSpacing: -0.6,
                      color: c.textPrimary,
                    ),
                  ),
                  const Spacer(),
                  IconButton(
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
                ],
              ),
              // Chips are 36 drawn inside a 44 target: 4 less above and
              // below keeps the canvas's 24 and 18.
              const SizedBox(height: 20),
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
              const SizedBox(height: 14),
              if (all == null)
                Text(
                  spaces.hasError
                      ? "We couldn't load your spaces. Pull down to try again."
                      : '',
                  style: SettloTypography.figtree(13, color: c.textSecondary),
                )
              else if (all.isEmpty)
                const _NoSpaces()
              else
                for (final (i, s) in shown.indexed) ...[
                  if (i > 0) const SizedBox(height: 12),
                  _SpaceCard(s),
                ],
              if (pending.isNotEmpty) ...[
                const SizedBox(height: 22),
                Text('INVITE PENDING', style: sectionLabel(c)),
                const SizedBox(height: 10),
                for (final (i, (space, member)) in pending.indexed) ...[
                  if (i > 0) const SizedBox(height: SettloSpacing.x1),
                  _PendingCard(space: space, member: member),
                ],
              ],
            ],
          ),
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
            style: SettloTypography.figtree(
              13,
              color: c.textSecondary,
            ).copyWith(height: 1.5),
          ),
          const SizedBox(height: 18),
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
    final small = SettloTypography.figtree(11, color: c.textSecondary);
    final total = s.monthTotal.value;
    int percent(Paise part) => (part.value * 100 / total).round();
    return MergeSemantics(
      child: InkWell(
        borderRadius: BorderRadius.circular(SettloRadius.card),
        onTap: () => context.go(SettloRoutes.space(s.id)),
        child: SCard(
          padding: const EdgeInsets.fromLTRB(20, 18, 20, 18),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  SpaceKindTile(s.kind),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          s.name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: SettloTypography.figtree(
                            16,
                            color: c.textPrimary,
                          ),
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
                          style: SettloTypography.figtree(
                            12,
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
                const SizedBox(height: 6),
                Row(
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
            if (i > 0) const SizedBox(width: 6),
            Expanded(
              flex: m.monthPaid.value,
              child: Container(
                height: 6,
                decoration: BoxDecoration(
                  color: m.isYou ? c.textPrimary : c.surfaceHighest,
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

class _PendingCard extends StatelessWidget {
  const new({required this.space, required this.member});

  final SpaceSummary space;
  final SpaceMember member;

  @override
  Widget build(BuildContext context) {
    final c = SettloColors.of(context);
    final b = member.balance;
    final number = maskPhone(member.phone);
    String detail(String amount) => b.value == 0
        ? 'Added to ${space.name} as $number'
        : '$amount in ${space.name} is recorded against $number';
    return SCard(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      child: MergeSemantics(
        child: Row(
          children: [
            SAvatar(member.name, size: 36),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    "${member.name} hasn't joined yet",
                    style: SettloTypography.figtree(14, color: c.textPrimary),
                  ),
                  Text(
                    detail(formatInr(Paise(b.value.abs()))),
                    semanticsLabel: detail(spokenInr(Paise(b.value.abs()))),
                    style: SettloTypography.figtree(
                      12,
                      color: c.textSecondary,
                    ).copyWith(height: 1.3),
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
