import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:settlo_activity/src/activity_provider.dart';
import 'package:settlo_core/settlo_core.dart';
import 'package:settlo_platform/settlo_platform.dart';

const _months = [
  'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', //
  'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
];

/// `5 Nov`, on the phone's calendar.
String _dayMonth(DateTime d) {
  final l = d.toLocal();
  return '${l.day} ${_months[l.month - 1]}';
}

/// The Activity tab (canvas Activity, note n30): what waits for your
/// confirmation on top, then everything that happened in your spaces and
/// loans, edits with their before and after values. 'Needs you' narrows
/// it to what waits for you. Answering opens the space's or loan's own
/// confirmation, so the rules live in one place.
class ActivityScreen extends ConsumerStatefulWidget {
  /// The Activity screen.
  const new({super.key});

  @override
  ConsumerState<ActivityScreen> createState() => _ActivityScreenState();
}

class _ActivityScreenState extends ConsumerState<ActivityScreen> {
  bool _needsYouOnly = false;

  /// Answering is open; another tap must not open a second one.
  bool _opening = false;

  @override
  void initState() {
    super.initState();
    // Ask to post the ongoing notification here, where a settle-up is
    // waiting for you, never at launch. Android asks at most once.
    var asked = false;
    ref.listenManual(needsYouProvider, (_, next) {
      if (asked || settleUpActivityFor(next.value ?? const []) == null) return;
      asked = true;
      unawaited(ref.read(liveActivitiesProvider).requestPermission());
    }, fireImmediately: true);
  }

  Future<void> _refresh() async {
    ref
      ..invalidate(needsYouProvider)
      ..invalidate(activityFeedProvider);
    await Future.wait([
      ref.read(needsYouProvider.future),
      ref.read(activityFeedProvider.future),
    ]).catchError((_) => const <Object>[]);
  }

  Future<void> _review(PendingAnswer a) async {
    // The push lands only on the next frame; a second tap in this one
    // must not open the confirmation twice.
    if (_opening) return;
    _opening = true;
    try {
      await context.push(
        a.isRepayment
            ? SettloRoutes.confirmRepayment(a.id)
            : SettloRoutes.confirmSettlement(a.spaceId!, a.id),
      );
    } finally {
      _opening = false;
    }
    // Answered here or not, show what is true now.
    if (mounted) await _refresh();
  }

  @override
  Widget build(BuildContext context) {
    final c = SettloColors.of(context);
    final media = MediaQuery.of(context);
    final needs = ref.watch(needsYouProvider);
    final feed = ref.watch(activityFeedProvider);
    final pending = needs.value ?? const <PendingAnswer>[];
    final entries = feed.value?.entries;
    final muted = SettloTypography.figtree(13, color: c.textSecondary);

    Widget empty(String title, String body) => SCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            title,
            style: SettloTypography.figtree(
              17,
              weight: FontWeight.w500,
              color: c.textPrimary,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            body,
            style: SettloTypography.figtree(14, color: c.textSecondary),
          ),
        ],
      ),
    );

    final children = <Widget>[
      Text(
        'Activity',
        style: SettloTypography.figtree(
          24,
          weight: FontWeight.w500,
          letterSpacing: -0.6,
          color: c.textPrimary,
        ),
      ),
      const SizedBox(height: 12),
      Wrap(
        spacing: 8,
        children: [
          SChip(
            label: 'All',
            selected: !_needsYouOnly,
            onSelected: (_) => setState(() => _needsYouOnly = false),
          ),
          SChip(
            label: pending.isEmpty
                ? 'Needs you'
                : 'Needs you · ${pending.length}',
            selected: _needsYouOnly,
            onSelected: (_) => setState(() => _needsYouOnly = true),
          ),
        ],
      ),
      const SizedBox(height: 14),
      if (pending.isNotEmpty) ...[
        _NeedsYouCard(pending, onReview: _review),
        const SizedBox(height: 8),
      ],
      if (_needsYouOnly) ...[
        if (needs.hasError && needs.value == null)
          Text("We couldn't load this. Pull down to try again.", style: muted)
        else if (needs.hasValue && pending.isEmpty)
          empty(
            'Nothing needs you',
            'Repayments and settle-ups waiting for your confirmation '
                'show up here.',
          ),
      ] else if (entries == null)
        Text(
          feed.hasError
              ? "We couldn't load activity. Pull down to try again."
              : '',
          style: muted,
        )
      else if (entries.isEmpty)
        empty(
          'No activity yet',
          'Expenses, settle-ups and repayments in your spaces and loans '
              'show up here, edits included.',
        )
      else
        ..._sections(context, entries),
    ];

    return Scaffold(
      body: RefreshIndicator(
        onRefresh: _refresh,
        child: NotificationListener<ScrollNotification>(
          onNotification: (n) {
            if (!_needsYouOnly && n.metrics.extentAfter < 600) {
              unawaited(ref.read(activityFeedProvider.notifier).loadMore());
            }
            return false;
          },
          child: ListView(
            padding: EdgeInsets.fromLTRB(
              SettloSpacing.screenMargin,
              math.max(media.padding.top, 44) + 16,
              SettloSpacing.screenMargin,
              media.padding.bottom + SettloSpacing.x2,
            ),
            children: children,
          ),
        ),
      ),
    );
  }

  /// The feed under Today, This week and Earlier headings.
  List<Widget> _sections(BuildContext context, List<ActivityEntry> entries) {
    final c = SettloColors.of(context);
    final now = ref.watch(activityNowProvider);
    final today = DateTime(now.year, now.month, now.day);
    String heading(DateTime at) {
      final l = at.toLocal();
      final day = DateTime(l.year, l.month, l.day);
      if (!day.isBefore(today)) return 'Today';
      if (today.difference(day).inDays < 7) return 'This week';
      return 'Earlier';
    }

    final out = <Widget>[];
    String? current;
    for (final (i, e) in entries.indexed) {
      final h = heading(e.at);
      if (h != current) {
        current = h;
        out.add(
          Padding(
            padding: EdgeInsets.only(top: i == 0 ? 12 : 16, bottom: 2),
            child: Semantics(
              header: true,
              child: Text(
                h,
                style: SettloTypography.figtree(12, color: c.textSecondary),
              ),
            ),
          ),
        );
      }
      final last = i == entries.length - 1 || heading(entries[i + 1].at) != h;
      out.add(_EntryRow(e, divider: !last));
    }
    return out;
  }
}

/// The top card: each settle-up and repayment waiting for you, with a
/// Review action that opens its confirmation.
class _NeedsYouCard extends StatelessWidget {
  const new(this.pending, {required this.onReview});

  final List<PendingAnswer> pending;
  final ValueChanged<PendingAnswer> onReview;

  @override
  Widget build(BuildContext context) {
    final c = SettloColors.of(context);
    return SCard(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (final (i, a) in pending.indexed) ...[
            if (i > 0)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 12),
                child: Divider(height: 1, thickness: 1, color: c.hairline),
              ),
            _PendingRow(a, onReview: () => onReview(a)),
          ],
        ],
      ),
    );
  }
}

class _PendingRow extends StatelessWidget {
  const new(this.answer, {required this.onReview});

  final PendingAnswer answer;
  final VoidCallback onReview;

  @override
  Widget build(BuildContext context) {
    final c = SettloColors.of(context);
    final a = answer;
    final what = a.isRepayment ? 'repayment' : 'settle-up';
    String title(String amount) => '${a.counterparty} recorded a $amount $what';
    final detail = [
      ?a.spaceName,
      'needs your confirmation',
      _dayMonth(a.paidOn),
    ].join(' · ');
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            SAvatar(a.counterparty, size: 36),
            const SizedBox(width: 12),
            Expanded(
              child: Semantics(
                label: '${title(spokenInr(a.amount))}, $detail',
                excludeSemantics: true,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title(formatInr(a.amount)),
                      style: SettloTypography.figtree(14, color: c.textPrimary),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      detail,
                      style: SettloTypography.figtree(
                        12,
                        color: c.textSecondary,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        _ReviewPill(onTap: onReview),
      ],
    );
  }
}

/// Review: the card's primary action, 36 drawn inside a 44 target.
class _ReviewPill extends StatelessWidget {
  const new({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = SettloColors.of(context);
    return SPressable(
      onTap: onTap,
      ringRadius: BorderRadius.circular(SettloRadius.pill),
      child: ConstrainedBox(
        constraints: const BoxConstraints(
          minHeight: SettloSpacing.minTouchTarget,
          minWidth: SettloSpacing.minTouchTarget,
        ),
        child: Align(
          alignment: Alignment.centerLeft,
          widthFactor: 1,
          heightFactor: 1,
          child: Container(
            height: 36,
            padding: const EdgeInsets.symmetric(horizontal: 16),
            decoration: ShapeDecoration(
              color: c.action,
              shape: const StadiumBorder(),
            ),
            child: Center(
              widthFactor: 1,
              child: Text(
                'Review',
                style: SettloTypography.figtree(
                  13,
                  weight: FontWeight.w500,
                  color: c.onAction,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// One feed line: who did what, where, and the amount in its tone.
class _EntryRow extends StatelessWidget {
  const new(this.entry, {required this.divider});

  final ActivityEntry entry;
  final bool divider;

  @override
  Widget build(BuildContext context) {
    final c = SettloColors.of(context);
    final e = entry;
    final (title, detail, spokenDetail) = _describe(e);
    return Container(
      constraints: const BoxConstraints(
        minHeight: SettloSpacing.minTouchTarget,
      ),
      padding: const EdgeInsets.symmetric(vertical: 13),
      decoration: divider
          ? BoxDecoration(
              border: Border(bottom: BorderSide(color: c.hairline)),
            )
          : null,
      child: MergeSemantics(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SAvatar(switch (e.kind) {
              ActivityKind.loan ||
              ActivityKind.repayment => e.counterparty ?? _who(e),
              _ => e.actor ?? _who(e),
            }, size: 36),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text.rich(
                    title,
                    style: SettloTypography.figtree(
                      14,
                      color: c.textPrimary,
                    ).copyWith(height: 1.4),
                  ),
                  const SizedBox(height: 3),
                  Semantics(
                    label: spokenDetail,
                    excludeSemantics: true,
                    child: Text(
                      detail,
                      style: SettloTypography.figtree(
                        12,
                        color: c.textSecondary,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            if (e.amount case final amount? when e.kind != ActivityKind.member)
              Padding(
                padding: const EdgeInsets.only(left: 8),
                child: MoneyText(amount, tone: e.tone, size: 14),
              ),
          ],
        ),
      ),
    );
  }
}

/// Who acted, as the row names them.
String _who(ActivityEntry e) => e.byYou ? 'You' : e.actor ?? 'Someone';

/// The row's title, its detail line, and the detail as read aloud (amounts
/// in rupees, never glyphs).
(TextSpan, String, String) _describe(ActivityEntry e) {
  final who = _who(e);
  final bold = SettloTypography.figtree(14, weight: FontWeight.w500);
  TextSpan line(String before, [String? name, String after = '']) => TextSpan(
    children: [
      TextSpan(text: before),
      if (name != null) TextSpan(text: name, style: bold),
      if (after.isNotEmpty) TextSpan(text: after),
    ],
  );
  final space = e.spaceName;
  final loan = 'Loan with ${e.counterparty ?? 'them'}';
  final date = _dayMonth(e.at);
  // An edit shows what changed: the amount before and after, and the old
  // name when it was renamed.
  final changed = <(String, String)>[
    if (e.action == ActivityAction.edited) ...[
      if ((e.beforeAmount, e.amount) case (final b?, final a?) when b != a)
        (
          '${formatInr(b)} → ${formatInr(a)}',
          '${spokenInr(b)} to ${spokenInr(a)}',
        ),
      if (e.beforeDescription case final b?
          when b != e.description && b.isNotEmpty)
        ('was $b', 'was $b'),
    ],
  ];
  final where = e.kind == ActivityKind.repayment || e.kind == ActivityKind.loan
      ? loan
      : space ?? '';
  final status = switch (e.status) {
    ActivityStatus.pending when e.action != ActivityAction.confirmed =>
      'waiting for confirmation',
    ActivityStatus.disputed when e.action != ActivityAction.disputed =>
      'marked as not received',
    _ => null,
  };
  final parts = [
    ...changed,
    (where, where),
    if (status != null) (status, status),
    (date, date),
  ].where((p) => p.$1.isNotEmpty);
  final detail = parts.map((p) => p.$1).join(' · ');
  final spoken = parts.map((p) => p.$2).join(', ');
  final desc = e.description ?? 'an expense';
  final verb = switch (e.action) {
    ActivityAction.created => 'added',
    ActivityAction.edited => 'edited',
    ActivityAction.deleted => 'deleted',
    ActivityAction.restored => 'restored',
    _ => e.action.name,
  };
  final cp = e.counterparty ?? 'They';
  final title = switch (e.kind) {
    ActivityKind.expense => line('$who $verb ', desc),
    ActivityKind.settlement => switch (e.action) {
      ActivityAction.created when e.toYou == true && !e.byYou => line(
        '$who settled with you',
      ),
      ActivityAction.created => line('$who recorded a settle-up'),
      ActivityAction.confirmed => line('$who confirmed a settle-up'),
      ActivityAction.disputed => line("$who said a settle-up didn't arrive"),
      _ => line('$who $verb a settle-up'),
    },
    ActivityKind.repayment => switch (e.action) {
      ActivityAction.confirmed => line(
        '${e.toYou == true ? cp : 'You'} repaid · '
        '${e.byYou ? 'you' : cp} confirmed',
      ),
      ActivityAction.disputed => line("$who said a repayment didn't arrive"),
      _ => line('$who recorded a repayment'),
    },
    ActivityKind.loan => switch (e.action) {
      ActivityAction.closed => line('$loan is fully repaid'),
      _ => line('$who recorded a loan'),
    },
    ActivityKind.member when e.linkOnly => line(
      "Someone with your link said it isn't them. The invite to ",
      e.description ?? 'that person',
      ' is still open.',
    ),
    ActivityKind.member => line(
      '',
      e.description ?? 'A number',
      " said it isn't them",
    ),
  };
  return (title, detail, spoken);
}
