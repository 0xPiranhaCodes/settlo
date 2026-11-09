import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:settlo_core/settlo_core.dart';
import 'package:settlo_spaces/src/glyphs.dart';
import 'package:settlo_spaces/src/text.dart';

const _months = [
  'January', 'February', 'March', 'April', 'May', 'June', //
  'July', 'August', 'September', 'October', 'November', 'December',
];

/// Space · empty (SpaceEmpty artboard): a space with nothing recorded,
/// the normal state for its first day.
///
/// Expenses can be added straight away; the card says the others see them
/// on joining, so nobody waits. Members who have not joined show their
/// masked number. The two set-up tasks are offered once, here (canvas note
/// n42).
class SpaceEmptyView extends StatelessWidget {
  /// The empty state of [space].
  const new(this.space, {super.key});

  /// The space shown.
  final SpaceSummary space;

  @override
  Widget build(BuildContext context) {
    final c = SettloColors.of(context);
    final media = MediaQuery.of(context);
    final members = [space.you, ...space.others];
    final waiting = [
      for (final m in space.others)
        if (!m.joined) m.name,
    ];
    final month = space.month ?? DateTime.now();
    final caption = SettloTypography.figtree(
      13,
      color: c.textSecondary,
    ).copyWith(height: 1.5);
    return Scaffold(
      body: DefaultTextStyle.merge(
        style: const TextStyle(letterSpacing: 0, height: 1.2),
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
                SizedBox(
                  width: 96,
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: IconButton(
                      tooltip: 'Back',
                      onPressed: () => context.canPop()
                          ? context.pop()
                          : context.go(SettloRoutes.spaces),
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
                        SpacesGlyph.back,
                        color: c.textPrimary,
                        size: 22,
                      ),
                    ),
                  ),
                ),
                Expanded(
                  child: Text(
                    space.name,
                    textAlign: TextAlign.center,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: SettloTypography.figtree(
                      15,
                      weight: FontWeight.w500,
                      color: c.textPrimary,
                    ),
                  ),
                ),
                SizedBox(
                  width: 96,
                  child: Align(
                    alignment: Alignment.centerRight,
                    child: ExcludeSemantics(
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          for (final (i, m) in members.take(3).indexed)
                            // Overlap by 8 and stay flush with the margin.
                            Transform.translate(
                              offset: Offset(
                                8.0 * (math.min(members.length, 3) - 1 - i),
                                0,
                              ),
                              child: Opacity(
                                opacity: m.joined ? 1 : 0.5,
                                child: SAvatar(m.name, size: 30),
                              ),
                            ),
                        ],
                      ),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 20),
            SCard(
              hero: true,
              padding: const EdgeInsets.all(22),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    _months[month.month - 1].toUpperCase(),
                    style: sectionLabel(c),
                  ),
                  const SizedBox(height: SettloSpacing.x1),
                  const Align(
                    alignment: Alignment.centerLeft,
                    child: MoneyText(
                      Paise.zero,
                      size: 40,
                      tone: MoneyTone.settled,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(switch (waiting) {
                    [] when space.others.isEmpty => 'No expenses yet.',
                    [] =>
                      'No expenses yet. You can add them now — everyone '
                          'here sees them straight away.',
                    [_] =>
                      'No expenses yet. You can add them now — '
                          '${waiting.single} will see everything the moment '
                          'their number is verified.',
                    _ =>
                      'No expenses yet. You can add them now — '
                          '${joinNames(waiting)} will see everything the '
                          'moment their numbers are verified.',
                  }, style: caption),
                  const SizedBox(height: 18),
                  SPrimaryButton(
                    label: 'Add first expense',
                    icon: SpacesIcon(
                      SpacesGlyph.plus,
                      color: c.onAction,
                      size: 18,
                      stroke: 1.9,
                    ),
                    onPressed: () => context.go(SettloRoutes.addExpense),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
            SCard(
              padding: const EdgeInsets.fromLTRB(20, 18, 20, 8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    children: [
                      Expanded(child: Text('MEMBERS', style: sectionLabel(c))),
                      Text(
                        '${members.where((m) => m.joined).length} OF '
                        '${members.length} JOINED',
                        style: sectionLabel(c),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  for (final (i, m) in members.indexed)
                    _MemberRow(m, divider: i < members.length - 1),
                ],
              ),
            ),
            const SizedBox(height: 12),
            SCard(
              padding: const EdgeInsets.fromLTRB(20, 18, 20, 8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text('SET UP ONCE', style: sectionLabel(c)),
                  const SizedBox(height: 10),
                  const _SetUpRow(
                    glyph: SpacesGlyph.clock,
                    label: 'Add rent as a monthly expense',
                    route: SettloRoutes.addExpense,
                    divider: true,
                  ),
                  const _SetUpRow(
                    glyph: SpacesGlyph.card,
                    label: 'Add your UPI ID so settle-ups are one tap',
                    route: SettloRoutes.profile,
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

BoxDecoration? _divider(SettloColors c, {required bool on}) => on
    ? BoxDecoration(
        border: Border(bottom: BorderSide(color: c.hairline)),
      )
    : null;

class _MemberRow extends StatelessWidget {
  const new(this.member, {required this.divider});

  final SpaceMember member;
  final bool divider;

  @override
  Widget build(BuildContext context) {
    final c = SettloColors.of(context);
    final m = member;
    return MergeSemantics(
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 10),
        decoration: _divider(c, on: divider),
        child: Row(
          children: [
            SAvatar(m.name, size: 36),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    m.isYou ? 'You' : m.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: SettloTypography.figtree(14, color: c.textPrimary),
                  ),
                  if (!m.joined)
                    Text(
                      '${maskPhone(m.phone)} · not joined yet',
                      style: SettloTypography.figtree(
                        12,
                        color: c.textSecondary,
                      ),
                    ),
                ],
              ),
            ),
            if (m.isOwner)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                decoration: BoxDecoration(
                  border: Border.all(color: c.textSecondary),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(
                  'admin',
                  style: SettloTypography.figtree(
                    11,
                    color: c.textSecondary,
                  ).copyWith(height: 1.3),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _SetUpRow extends StatelessWidget {
  const new({
    required this.glyph,
    required this.label,
    required this.route,
    this.divider = false,
  });

  final SpacesGlyph glyph;
  final String label;
  final String route;
  final bool divider;

  @override
  Widget build(BuildContext context) {
    final c = SettloColors.of(context);
    return MergeSemantics(
      child: InkWell(
        onTap: () => context.go(route),
        child: Container(
          constraints: const BoxConstraints(
            minHeight: SettloSpacing.minTouchTarget,
          ),
          padding: const EdgeInsets.symmetric(vertical: 10),
          decoration: _divider(c, on: divider),
          child: Row(
            children: [
              SpacesIcon(glyph, color: c.textPrimary, size: 18),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  label,
                  style: SettloTypography.figtree(14, color: c.textPrimary),
                ),
              ),
              SpacesIcon(SpacesGlyph.chevron, color: c.textMuted, size: 18),
            ],
          ),
        ),
      ),
    );
  }
}
