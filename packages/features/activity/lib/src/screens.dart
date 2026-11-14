import 'dart:async';

import 'package:flutter/cupertino.dart';
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

/// Wraps a scoped activity feed in its destination's shared sheet chrome.
typedef ActivitySheetBuilder = Widget Function(
  List<Widget> children,
  Future<void> Function() onRefresh,
);

/// The Activity tab (canvas Activity, note n30): what waits for your
/// confirmation on top, then everything that happened in your spaces and
/// loans, edits with their before and after values. 'Needs you' narrows
/// it to what waits for you; a space's chip or Loans narrows the feed
/// (#109). Answering opens the space's or loan's own confirmation, so the
/// rules live in one place.
///
/// The other tabs' bell counts what arrived since Activity was last open,
/// on any of your devices; opening the tab marks it seen. Someone else's
/// edit can be questioned with a short note that the space's members see on
/// its row.
class ActivityScreen extends StatelessWidget {
  /// The global Activity tab, or a fixed space feed with its own header.
  const new({this.spaceId, this.sheetBuilder, super.key});

  /// A fixed space filter, isolated from the global tab's selection.
  final String? spaceId;

  /// Builds a shared sheet around the feed, retaining refresh and pagination.
  final ActivitySheetBuilder? sheetBuilder;

  @override
  Widget build(BuildContext context) {
    final view = _ActivityView(spaceId: spaceId, sheetBuilder: sheetBuilder);
    if (spaceId == null) return view;
    return ProviderScope(
      key: ValueKey(spaceId),
      overrides: [
        activityFilterProvider.overrideWith(
          () => ActivityFilterController(
            initialFilter: (spaceId: spaceId, loansOnly: false),
          ),
        ),
        activityFeedProvider.overrideWith(ActivityFeedController.new),
      ],
      child: view,
    );
  }
}

class _ActivityView extends ConsumerStatefulWidget {
  /// The Activity screen.
  const new({this.spaceId, this.sheetBuilder});

  final String? spaceId;
  final ActivitySheetBuilder? sheetBuilder;

  @override
  ConsumerState<_ActivityView> createState() => _ActivityScreenState();
}

class _ActivityScreenState extends ConsumerState<_ActivityView> {
  bool _needsYouOnly = false;

  /// iOS search over the loaded feed; empty shows everything.
  String _query = '';

  /// Answering is open; another tap must not open a second one.
  bool _opening = false;

  /// Whether the tab is the one showing; the shell keeps the others built.
  bool _showing = false;

  final _scroll = ScrollController();

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

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // The shell turns tickers off for the tabs it hides, so this is true
    // exactly while Activity is the tab on screen.
    final showing = TickerMode.valuesOf(context).enabled;
    if (widget.spaceId == null && showing && !_showing) unawaited(_seen());
    _showing = showing;
  }

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  /// Marks what arrived since Activity was last open as seen on every
  /// device, clearing the other tabs' bell.
  Future<void> _seen() async {
    // Called while the tab builds; providers may only change after it.
    await Future<void>.value();
    if (!mounted) return;
    try {
      final unread = await ref.refresh(activityUnreadProvider.future);
      if (!mounted || unread == 0) return;
      await ref.read(activityRepositoryProvider).markSeen();
      if (mounted) ref.invalidate(activityUnreadProvider);
    } on Exception {
      // The bell stays as it was; the next open tries again.
    }
  }

  Future<void> _refresh() async {
    ref
      ..invalidate(needsYouProvider)
      ..invalidate(activityFeedProvider);
    await Future.wait([
      ref.read(needsYouProvider.future),
      ref.read(activityFeedProvider.future),
    ]).catchError((_) => const <Object>[]);
    if (mounted && widget.spaceId == null) await _seen();
  }

  /// Shows the feed through [filter].
  void _show(ActivityFilter filter) {
    setState(() => _needsYouOnly = false);
    ref.read(activityFilterProvider.notifier).show(filter);
  }

  Future<void> _question(ActivityEntry e) async {
    if (_opening) return;
    _opening = true;
    try {
      final sent = await showSettloSheet<bool>(
        context: context,
        builder: (_) => _QuestionSheet(e),
      );
      // The note is on the row now, from the server or from the queue.
      if (sent ?? false) ref.invalidate(activityFeedProvider);
    } finally {
      _opening = false;
    }
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
    final needs = ref.watch(needsYouProvider);
    final feed = ref.watch(activityFeedProvider);
    final filter = ref.watch(activityFilterProvider);
    final spaces = ref.watch(activitySpacesProvider).value ?? const [];
    final pending = [
      for (final answer in needs.value ?? const <PendingAnswer>[])
        if (widget.spaceId == null || answer.spaceId == widget.spaceId) answer,
    ];
    // Never another filter's rows while this one loads.
    final entries = feed.value?.filter == filter
        ? [
            for (final e in feed.value!.entries)
              if (_query.isEmpty || _matches(e)) e,
          ]
        : null;
    final ios = Theme.of(context).platform == TargetPlatform.iOS;
    final muted = SettloTypography.subheadline(color: c.textSecondary);

    Widget empty(String title, String body) {
      final content = Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(title, style: SettloTypography.headline(color: c.textPrimary)),
          const SizedBox(height: SettloSpacing.x1),
          Text(body, style: SettloTypography.body(color: c.textSecondary)),
        ],
      );
      return widget.sheetBuilder == null
          ? _FeedGroup(child: content)
          : SCard(child: content);
    }

    final children = <Widget>[
      if (widget.sheetBuilder == null)
        const SettloNavigationHeader(
          title: 'Activity',
          // No bell: this screen is the notifications list (#197).
          trailing: SettloTabActions(onBell: null),
        ),
      if (ios) ...[
        if (widget.sheetBuilder != null)
          const SizedBox(height: SettloSpacing.x1),
        SSearchField(onChanged: (q) => setState(() => _query = q)),
      ],
      if (ios || widget.sheetBuilder != null)
        const SizedBox(height: SettloSpacing.x2),
      // One row, as on the canvas; it scrolls once the spaces outgrow it.
      if (widget.spaceId == null)
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: CupertinoSlidingSegmentedControl<String>(
            proportionalWidth: true,
            backgroundColor: c.surfaceRaised,
            thumbColor: c.surface,
            groupValue: _needsYouOnly
                ? 'needs'
                : filter.loansOnly
                ? 'loans'
                : filter.spaceId ?? 'all',
            onValueChanged: (value) {
              if (value == null) return;
              if (value == 'needs') {
                setState(() => _needsYouOnly = true);
              } else {
                _show(
                  value == 'all'
                      ? allActivity
                      : (
                          spaceId: value == 'loans' ? null : value,
                          loansOnly: value == 'loans',
                        ),
                );
              }
            },
            children: {
              for (final entry in <String, String>{
                'all': 'All',
                'needs': pending.isEmpty
                    ? 'Needs you'
                    : 'Needs you · ${pending.length}',
                for (final s in spaces) s.id: s.name,
                'loans': 'Loans',
              }.entries)
                entry.key: ConstrainedBox(
                  constraints: const BoxConstraints(minHeight: 40),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 10,
                    ),
                    child: Text(
                      entry.value,
                      style: SettloTypography.subheadline(color: c.textPrimary),
                    ),
                  ),
                ),
            },
          ),
        ),
      const SizedBox(height: SettloSpacing.x2),
      if (pending.isNotEmpty) ...[
        if (widget.sheetBuilder == null)
          _NeedsYouCard(pending, onReview: _review)
        else
          _ScopedNeedsYouCard(pending, onReview: _review),
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
      else if (entries.isEmpty && _query.isNotEmpty)
        Text('No activity matches "$_query".', style: muted)
      else if (entries.isEmpty)
        empty(
          filter == allActivity ? 'No activity yet' : 'Nothing here yet',
          filter.loansOnly
              ? 'Loans and repayments you are part of show up here.'
              : filter.spaceId != null
              ? 'Expenses and settle-ups in this space show up here, '
                    'edits included.'
              : 'Expenses, settle-ups and repayments in your spaces and '
                    'loans show up here, edits included.',
        )
      else if (!ios || widget.sheetBuilder != null)
        for (final (heading, rows) in _sections(context, entries)) ...[
          heading,
          if (widget.sheetBuilder != null)
            ...rows
          else
            SGroup(margin: EdgeInsets.zero, children: rows),
        ],
    ];
    final groups =
        widget.sheetBuilder == null &&
            ios &&
            !_needsYouOnly &&
            (entries?.isNotEmpty ?? false)
        ? _sections(context, entries!)
        : null;
    const margin = EdgeInsets.symmetric(horizontal: SettloTabScaffold.inset);
    Widget listenForMore(Widget child) =>
        NotificationListener<ScrollNotification>(
          onNotification: (n) {
            // The chips scroll sideways; only the feed's end loads more.
            if (!_needsYouOnly &&
                n.metrics.axis == Axis.vertical &&
                n.metrics.extentAfter < 600) {
              unawaited(ref.read(activityFeedProvider.notifier).loadMore());
            }
            return false;
          },
          child: child,
        );
    if (widget.sheetBuilder case final builder?) {
      return listenForMore(builder(children, _refresh));
    }
    return Scaffold(
      body: listenForMore(
        SettloTabScaffold(
          title: 'Activity',

          onRefresh: _refresh,
          controller: _scroll,
          slivers: groups == null
              ? null
              : [
                  SliverPadding(
                    padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
                    sliver: SliverList.list(
                      children: children.skip(1).toList(),
                    ),
                  ),
                  for (final (heading, rows) in groups)
                    SliverMainAxisGroup(
                      slivers: [
                        PinnedHeaderSliver(
                          child: ColoredBox(
                            color: c.background,
                            child: Padding(padding: margin, child: heading),
                          ),
                        ),
                        SliverToBoxAdapter(
                          child: Padding(
                            padding: margin,
                            child: SGroup(
                              margin: EdgeInsets.zero,
                              children: rows,
                            ),
                          ),
                        ),
                      ],
                    ),
                  SliverToBoxAdapter(
                    child: SizedBox(
                      height: MediaQuery.paddingOf(context).bottom + 16,
                    ),
                  ),
                ],
          // With its own controller a short feed would not scroll, and
          // so could not be pulled down to refresh.
          children: children,
        ),
      ),
    );
  }

  bool _matches(ActivityEntry e) {
    final (title, detail, _) = _describe(e);
    return searchMatches(_query, '${title.toPlainText()} $detail');
  }

  /// The feed under Today, This week and Earlier headings: each heading
  /// with its rows.
  List<(Widget, List<Widget>)> _sections(
    BuildContext context,
    List<ActivityEntry> entries,
  ) {
    final now = ref.watch(activityNowProvider);
    final today = DateTime(now.year, now.month, now.day);
    String heading(DateTime at) {
      final l = at.toLocal();
      final day = DateTime(l.year, l.month, l.day);
      if (!day.isBefore(today)) return 'Today';
      if (today.difference(day).inDays < 7) return 'This week';
      return 'Earlier';
    }

    final out = <(Widget, List<Widget>)>[];
    String? current;
    for (final (i, e) in entries.indexed) {
      final h = heading(e.at);
      if (h != current) {
        current = h;
        out.add((
          widget.sheetBuilder == null
              ? SSectionLabel(h)
              : Padding(
                  padding: EdgeInsets.only(top: i == 0 ? 12 : 16, bottom: 2),
                  child: Semantics(
                    header: true,
                    child: Text(
                      h,
                      style: SettloTypography.footnote(
                        color: SettloColors.of(context).textSecondary,
                      ),
                    ),
                  ),
                ),
          <Widget>[],
        ));
      }
      final last = i == entries.length - 1 || heading(entries[i + 1].at) != h;
      out.last.$2.add(
        widget.sheetBuilder == null
            ? _EntryRow(
                e,
                divider: !last,
                onQuestion: e.canQuestion
                    ? () => unawaited(_question(e))
                    : null,
              )
            : _ScopedEntryRow(
                e,
                divider: !last,
                onQuestion: e.canQuestion
                    ? () => unawaited(_question(e))
                    : null,
              ),
      );
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
    return SGroup(
      margin: EdgeInsets.zero,
      children: [
        for (final a in pending) ...[
          _PendingRow(a, onReview: () => onReview(a)),
          const SizedBox(height: 16),
        ],
      ],
    );
  }
}

class _PendingRow extends StatelessWidget {
  const new(this.answer, {required this.onReview});

  final PendingAnswer answer;
  final VoidCallback onReview;

  @override
  Widget build(BuildContext context) {
    final a = answer;
    final what = a.isRepayment ? 'repayment' : 'settle-up';
    String title(String amount) => '${a.counterparty} recorded a $amount $what';
    final detail = [
      ?a.spaceName,
      'needs your confirmation',
      _dayMonth(a.paidOn),
    ].join(' · ');
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SRow(
          title: title(formatInr(a.amount)),
          subtitle: detail,
          subtitleSemanticsLabel: '${title(spokenInr(a.amount))}, $detail',
          leading: Stack(
            children: [
              SAvatar(a.counterparty, size: 36),
              Positioned(
                right: 0,
                bottom: 0,
                child: Icon(
                  CupertinoIcons.clock,
                  size: 14,
                  color: SettloColors.of(context).pending,
                ),
              ),
            ],
          ),
          scaleLeading: true,
          separator: false,
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: _ReviewPill(onTap: onReview),
        ),
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
            constraints: const BoxConstraints(minHeight: 50),
            padding: const EdgeInsets.symmetric(horizontal: 16),
            decoration: ShapeDecoration(
              color: c.action.withValues(alpha: .1),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(14),
              ),
            ),
            child: Center(
              widthFactor: 1,
              child: Text(
                'Review',
                style: SettloTypography.subheadline(color: c.action),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// The newest real feed entries, composed for the populated Home screen.
///
/// This intentionally watches the same provider and uses the same row as the
/// Activity tab, so Home never invents or caches a second version of history.
class ActivityPreview extends ConsumerWidget {
  /// Creates the compact Home preview.
  const new({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final entries = ref.watch(activityFeedProvider).value?.entries;
    if (entries == null || entries.isEmpty) return const SizedBox.shrink();
    final shown = entries.take(3).toList();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            const Expanded(child: SSectionLabel('Recent activity')),
            IconButton(
              tooltip: 'See all activity',
              onPressed: () => context.go(SettloRoutes.activity),
              icon: const Icon(Icons.arrow_forward),
            ),
          ],
        ),
        SGroup(
          margin: EdgeInsets.zero,
          children: [
            for (final (i, entry) in shown.indexed)
              _EntryRow(entry, divider: i < shown.length - 1),
          ],
        ),
      ],
    );
  }
}

/// One feed line: who did what, where, and the amount in its tone, with
/// members' questions under it. With [onQuestion] the whole row is the
/// target for 'Question this', so the link in its detail need not be.
class _EntryRow extends StatelessWidget {
  const new(this.entry, {required this.divider, this.onQuestion});

  final ActivityEntry entry;
  final bool divider;
  final VoidCallback? onQuestion;

  @override
  Widget build(BuildContext context) {
    final e = entry;
    final (title, detail, spoken) = _describe(e);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SRow(
          title: title.toPlainText(),
          subtitle: onQuestion == null ? detail : '$detail · Question this',
          subtitleSemanticsLabel: onQuestion == null
              ? spoken
              : '$spoken, Question this',
          leading: SAvatar(switch (e.kind) {
            ActivityKind.loan ||
            ActivityKind.repayment => e.counterparty ?? _who(e),
            _ => e.actor ?? _who(e),
          }, size: 36),
          scaleLeading: true,
          trailing: e.amount != null && e.kind != ActivityKind.member
              ? MoneyText(
                  e.toYou == false ? -e.amount! : e.amount!,
                  signed: e.toYou != null,
                  tone: e.tone,
                  size: 17,
                )
              : null,
          separator: divider && e.questions.isEmpty,
          onTap: onQuestion,
        ),
        for (final q in e.questions)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
            child: Text(
              '${q.byYou ? 'You' : q.name ?? 'Someone'} asked: “${q.note}”',
              style: SettloTypography.footnote(
                color: SettloColors.of(context).textSecondary,
              ),
            ),
          ),
      ],
    );
  }
}

/// 'Question this': a short note to whoever made the edit.
class _QuestionSheet extends ConsumerStatefulWidget {
  const new(this.entry);

  final ActivityEntry entry;

  @override
  ConsumerState<_QuestionSheet> createState() => _QuestionSheetState();
}

class _QuestionSheetState extends ConsumerState<_QuestionSheet> {
  final _note = TextEditingController();
  bool _busy = false;
  bool _failed = false;

  @override
  void dispose() {
    _note.dispose();
    super.dispose();
  }

  Future<void> _send() async {
    setState(() {
      _busy = true;
      _failed = false;
    });
    try {
      await ref
          .read(activityRepositoryProvider)
          .question(widget.entry, _note.text);
      if (mounted) Navigator.of(context).pop(true);
    } on Exception {
      if (mounted) {
        setState(() {
          _busy = false;
          _failed = true;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = SettloColors.of(context);
    final e = widget.entry;
    final editor = e.actor ?? 'them';
    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 24, 20, 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'Question this edit',
              style: SettloTypography.headline(color: c.textPrimary),
            ),
            const SizedBox(height: SettloSpacing.x1),
            Text(
              'Ask $editor about the change to '
              '${e.description ?? 'this expense'}. Everyone in '
              '${e.spaceName ?? 'the space'} sees your note here in '
              'Activity.',
              style: SettloTypography.subheadline(color: c.textSecondary),
            ),
            const SizedBox(height: 16),
            Semantics(
              label: 'Your question',
              child: TextField(
                controller: _note,
                autofocus: true,
                maxLength: questionMaxLength,
                textCapitalization: TextCapitalization.sentences,
                onChanged: (_) => setState(() => _failed = false),
                style: SettloTypography.headline(color: c.textPrimary),
                decoration: const InputDecoration(
                  hintText: 'Why did this change?',
                  counterText: '',
                ),
              ),
            ),
            if (_failed) ...[
              const SizedBox(height: SettloSpacing.x2),
              Text(
                "We couldn't send that. Try again.",
                style: SettloTypography.subheadline(color: c.textPrimary),
              ),
            ],
            const SizedBox(height: 16),
            SPrimaryButton(
              label: _busy ? 'Sending…' : 'Send',
              onPressed: _busy || _note.text.trim().isEmpty ? null : _send,
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
  final bold = SettloTypography.body(weight: FontWeight.w500);
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
      ActivityAction.reminded => line('A gentle reminder to check your loan'),
      ActivityAction.due => line('An instalment was due yesterday'),
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

class _FeedGroup extends StatelessWidget {
  const new({required this.child});
  final Widget child;
  @override
  Widget build(BuildContext context) => SGroup(
    margin: EdgeInsets.zero,
    children: [Padding(padding: const EdgeInsets.all(16), child: child)],
  );
}

// Scoped sheet activity keeps its existing presentation; #278 phase 2b
// changes only the four tab roots.
class _ScopedNeedsYouCard extends StatelessWidget {
  const new(this.pending, {required this.onReview});

  final List<PendingAnswer> pending;
  final ValueChanged<PendingAnswer> onReview;

  @override
  Widget build(BuildContext context) {
    return SCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (final (i, a) in pending.indexed) ...[
            if (i > 0) const SizedBox(height: SettloSpacing.x2),
            _ScopedPendingRow(a, onReview: () => onReview(a)),
          ],
        ],
      ),
    );
  }
}

class _ScopedPendingRow extends StatelessWidget {
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
            const SizedBox(width: SettloSpacing.x2),
            Expanded(
              child: Semantics(
                label: '${title(spokenInr(a.amount))}, $detail',
                excludeSemantics: true,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title(formatInr(a.amount)),
                      style: SettloTypography.body(color: c.textPrimary),
                    ),
                    const SizedBox(height: 2),
                    Row(
                      children: [
                        Icon(Icons.schedule, size: 14, color: c.pending),
                        const SizedBox(width: 4),
                        Expanded(
                          child: Text(
                            detail,
                            style: SettloTypography.footnote(color: c.pending),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        _ScopedReviewPill(onTap: onReview),
      ],
    );
  }
}

/// Review: the card's primary action, 36 drawn inside a 44 target.
class _ScopedReviewPill extends StatelessWidget {
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
                style: SettloTypography.subheadline(color: c.onAction),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _ScopedEntryRow extends StatelessWidget {
  const new(this.entry, {required this.divider, this.onQuestion});

  final ActivityEntry entry;
  final bool divider;
  final VoidCallback? onQuestion;

  @override
  Widget build(BuildContext context) {
    final c = SettloColors.of(context);
    final e = entry;
    final (title, detail, spoken) = _describe(e);
    final spokenDetail = onQuestion == null ? spoken : '$spoken, Question this';
    final small = SettloTypography.footnote(
      color: e.status == ActivityStatus.pending ? c.pending : c.textSecondary,
    );
    final row = Container(
      constraints: const BoxConstraints(
        minHeight: SettloSpacing.minTouchTarget,
      ),
      padding: const EdgeInsets.symmetric(vertical: SettloSpacing.x2),
      child: MergeSemantics(
        child: SResponsiveRow(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SAvatar(switch (e.kind) {
              ActivityKind.loan ||
              ActivityKind.repayment => e.counterparty ?? _who(e),
              _ => e.actor ?? _who(e),
            }, size: 36),
            const SizedBox(width: SettloSpacing.x2),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text.rich(
                    title,
                    style: SettloTypography.body(color: c.textPrimary)
                        .copyWith(height: 1.4),
                  ),
                  const SizedBox(height: 3),
                  Semantics(
                    label: spokenDetail,
                    excludeSemantics: true,
                    child: Text.rich(
                      TextSpan(
                        text: detail,
                        children: [
                          if (onQuestion != null) ...[
                            const TextSpan(text: ' · '),
                            TextSpan(
                              text: 'Question this',
                              style: SettloTypography.footnote(color: c.action),
                            ),
                          ],
                        ],
                      ),
                      style: small,
                    ),
                  ),
                  for (final q in e.questions)
                    Padding(
                      padding: const EdgeInsets.only(top: 4),
                      child: Text(
                        '${q.byYou ? 'You' : q.name ?? 'Someone'} asked: '
                        '“${q.note}”',
                        style: small.copyWith(color: c.textPrimary),
                      ),
                    ),
                ],
              ),
            ),
            if (e.amount case final amount? when e.kind != ActivityKind.member)
              Padding(
                padding: const EdgeInsets.only(left: 8),
                child: MoneyText(
                  e.toYou == false ? -amount : amount,
                  signed: e.toYou != null,
                  tone: e.tone,
                  size: 14,
                ),
              ),
          ],
        ),
      ),
    );
    return switch (onQuestion) {
      final onTap? => SPressable(
        onTap: onTap,
        ringRadius: BorderRadius.circular(SettloRadius.button),
        child: row,
      ),
      null => row,
    };
  }
}
