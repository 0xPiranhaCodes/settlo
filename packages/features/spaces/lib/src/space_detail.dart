import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart';
import 'package:go_router/go_router.dart';
import 'package:settlo_activity/settlo_activity.dart';
import 'package:settlo_core/settlo_core.dart';
import 'package:settlo_platform/settlo_platform.dart';
import 'package:settlo_spaces/src/glyphs.dart';
import 'package:settlo_spaces/src/space_empty.dart';
import 'package:settlo_spaces/src/spaces_controller.dart';
import 'package:settlo_spaces/src/text.dart';

const _months = [
  'January', 'February', 'March', 'April', 'May', 'June', //
  'July', 'August', 'September', 'October', 'November', 'December',
];
const _weekdays = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];

/// The repaint boundary around the fair-share card, for colour probes.
const Key fairnessCardKey = ValueKey('space-fairness-card');

/// A space's ledger through [spaceLedgerRepositoryProvider], by space id.
/// Reloads whenever [ledgerRevisionProvider] is bumped.
final AsyncNotifierProviderFamily<SpaceLedgerController, SpaceLedger, String>
spaceLedgerProvider =
    AsyncNotifierProvider.family<SpaceLedgerController, SpaceLedger, String>(
      SpaceLedgerController.new,
    );

/// Loads a space's ledger and edits or deletes its expenses. Every change
/// bumps [ledgerRevisionProvider] (this ledger and Home reload) and
/// reloads [spacesProvider] for the balances.
class SpaceLedgerController extends AsyncNotifier<SpaceLedger> {
  /// The ledger of [spaceId].
  new(this.spaceId);

  /// The space shown.
  final String spaceId;

  @override
  Future<SpaceLedger> build() {
    ref.watch(ledgerRevisionProvider);
    return ref.watch(spaceLedgerRepositoryProvider).load(spaceId);
  }

  /// Saves [update]; a retry must pass the same [idempotencyKey].
  Future<void> edit(ExpenseUpdate update, {required String idempotencyKey}) =>
      _changed(
        ref
            .read(spaceLedgerRepositoryProvider)
            .updateExpense(update, idempotencyKey: idempotencyKey),
      );

  /// Deletes [expenseId]; a retry must pass the same [idempotencyKey].
  Future<void> delete(String expenseId, {required String idempotencyKey}) =>
      _changed(
        ref
            .read(spaceLedgerRepositoryProvider)
            .deleteExpense(expenseId, idempotencyKey: idempotencyKey),
      );

  /// Confirms pending settle-up [expense] as shown, as its payee; a retry
  /// must pass the same [idempotencyKey].
  Future<void> confirmSettlement(
    SpaceExpense expense, {
    required String idempotencyKey,
  }) => _changed(
    ref
        .read(spaceLedgerRepositoryProvider)
        .confirmSettlement(
          expense.id,
          amount: expense.amount,
          payerMemberId: expense.payers.single.memberId,
          idempotencyKey: idempotencyKey,
        ),
  );

  /// Disputes pending settle-up [expenseId] as its payee with [reason]; a
  /// retry must pass the same [idempotencyKey] and [reason].
  Future<void> disputeSettlement(
    String expenseId,
    String reason, {
    required String idempotencyKey,
  }) => _changed(
    ref
        .read(spaceLedgerRepositoryProvider)
        .disputeSettlement(expenseId, reason, idempotencyKey: idempotencyKey),
  );

  /// Loads the ledger again.
  Future<void> reload() async {
    ref.invalidateSelf();
    await future;
  }

  Future<void> _changed(Future<void> write) async {
    await write;
    ref.invalidate(spacesProvider);
    ref.read(ledgerRevisionProvider.notifier).bump();
    await future;
  }
}

/// The three tabs of a space with spending.
enum SpaceTab {
  /// SpaceExpenses: the month's shape and every expense.
  expenses,

  /// Space: who paid against their fair share, and how to settle.
  balances,

  /// Activity recorded in this space.
  activity,
}

/// A space with spending (SpaceExpenses and Space artboards), on [tab].
class SpaceDetailView extends ConsumerWidget {
  /// [space] on [tab].
  const new(this.space, {required this.tab, super.key});

  /// The space shown.
  final SpaceSummary space;

  /// The tab shown.
  final SpaceTab tab;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ledger = ref.watch(spaceLedgerProvider(space.id));
    final loaded = ledger.value;
    if (tab == SpaceTab.activity) {
      return ActivityScreen(
        spaceId: space.id,
        spaceName: space.name,
        navTrailing: SpaceAvatars(space),
        header: [
          SpaceHeader(space),
          const SizedBox(height: SettloSpacing.x3),
          _Top(space, loaded),
          _Tabs(space: space, tab: tab),
        ],
      );
    }
    final c = SettloColors.of(context);
    final media = MediaQuery.of(context);
    return Scaffold(
      body: DefaultTextStyle.merge(
        style: const TextStyle(letterSpacing: 0, height: 1.2),
        child: SettloScrollScaffold(
          title: 'Space',
          largeTitle: space.name,
          previousPageTitle: 'Spaces',
          trailing: SpaceAvatars(space),
          onRefresh: () async {
            ref.invalidate(spacesProvider);
            await ref.read(spaceLedgerProvider(space.id).notifier).reload();
          },
          padding: EdgeInsets.fromLTRB(
            SettloSpacing.screenMargin,
            math.max(media.padding.top, 44) + 16,
            SettloSpacing.screenMargin,
            media.padding.bottom + SettloSpacing.x2,
          ),
          children: [
            SpaceHeader(space),
            const SizedBox(height: SettloSpacing.x3),
            // On every segment, so the control never moves under the finger.
            _Top(space, loaded),
            _Tabs(space: space, tab: tab),
            const SizedBox(height: SettloSpacing.x2),
            if (loaded == null)
              Text(
                ledger.hasError
                    ? "We couldn't load this space. Pull down to try again."
                    : '',
                style: SettloTypography.subheadline(color: c.textSecondary),
              )
            else if (tab == SpaceTab.expenses)
              _ExpenseList(space, loaded)
            else ...[
              _FairnessCard(space, loaded),
              const SizedBox(height: SettloSpacing.x2),
              _SettleCard(space),
              if (loaded.categories.isNotEmpty) ...[
                const SizedBox(height: SettloSpacing.x2),
                _CategoriesCard(loaded),
              ],
            ],
          ],
        ),
      ),
    );
  }
}

/// The hero and the space's two actions, above the segments.
class _Top extends StatelessWidget {
  const new(this.space, this.ledger);

  final SpaceSummary space;
  final SpaceLedger? ledger;

  @override
  Widget build(BuildContext context) {
    final c = SettloColors.of(context);
    final largeText = MediaQuery.textScalerOf(context).scale(14) > 21;
    // Activity's screen has no space text style; the hero needs the same
    // height there, or the segments below it move.
    return DefaultTextStyle.merge(
      style: const TextStyle(letterSpacing: 0, height: 1.2),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _Hero(space, ledger),
          const SizedBox(height: SettloSpacing.x2),
          // The canvas pads these 16, not Material's 24, so both
          // labels fit side by side at 360.
          Theme(
            data: _compactButtons(Theme.of(context)),
            child: Flex(
              direction: largeText ? Axis.vertical : Axis.horizontal,
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: largeText
                  ? CrossAxisAlignment.stretch
                  : CrossAxisAlignment.center,
              children: [
                Flexible(
                  fit: largeText ? FlexFit.loose : FlexFit.tight,
                  child: SPrimaryButton(
                    label: 'Add expense',
                    icon: SpacesIcon(
                      SpacesGlyph.plus,
                      color: c.onAction,
                      size: 18,
                      stroke: 1.9,
                    ),
                    onPressed: () =>
                        context.push(SettloRoutes.addExpenseIn(space.id)),
                  ),
                ),
                SizedBox(
                  width: SettloSpacing.x2,
                  height: largeText ? SettloSpacing.x2 : 0,
                ),
                Flexible(
                  fit: largeText ? FlexFit.loose : FlexFit.tight,
                  child: SSecondaryButton(
                    label: 'Settle up',
                    onPressed: () =>
                        context.push(SettloRoutes.settleWith(space.id)),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: SettloSpacing.x3),
        ],
      ),
    );
  }
}

ThemeData _compactButtons(ThemeData theme) {
  const padding = WidgetStatePropertyAll(EdgeInsets.symmetric(horizontal: 16));
  return theme.copyWith(
    filledButtonTheme: FilledButtonThemeData(
      style: theme.filledButtonTheme.style?.copyWith(padding: padding),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: theme.outlinedButtonTheme.style?.copyWith(padding: padding),
    ),
  );
}

/// Your balance, the month's total and a sparkline of its daily spend
/// (canvas note n11). The amount is directional; spend stays neutral.
class _Hero extends StatelessWidget {
  const new(this.space, this.ledger);

  final SpaceSummary space;
  final SpaceLedger? ledger;

  @override
  Widget build(BuildContext context) {
    final c = SettloColors.of(context);
    final largeText = MediaQuery.textScalerOf(context).scale(14) > 21;
    final balance = space.balance;
    final today = ledger?.today ?? DateTime.now();
    final month = DateTime(today.year, today.month);
    final daily = List.filled(today.day, 0);
    for (final e in ledger?.expenses ?? const <SpaceExpense>[]) {
      if (!e.isSettlement &&
          !e.spentOn.isBefore(month) &&
          !e.spentOn.isAfter(today)) {
        daily[e.spentOn.day - 1] += e.amount.value;
      }
    }
    final monthName = _months[month.month - 1];
    final small = SettloTypography.caption1(color: c.textSecondary);
    return SCard(
      hero: true,
      padding: const EdgeInsets.all(SettloSpacing.x3),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Flex(
            direction: largeText ? Axis.vertical : Axis.horizontal,
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: largeText
                ? CrossAxisAlignment.start
                : CrossAxisAlignment.end,
            children: [
              Flexible(
                fit: largeText ? FlexFit.loose : FlexFit.tight,
                child: MergeSemantics(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(switch (balance.value) {
                        > 0 => 'YOU ARE OWED',
                        < 0 => 'YOU OWE',
                        _ => 'ALL SETTLED',
                      }, style: sectionLabel(c)),
                      const SizedBox(height: SettloSpacing.x1),
                      FittedBox(
                        fit: BoxFit.scaleDown,
                        alignment: Alignment.centerLeft,
                        child: MoneyText(
                          // Which way is in the label; the canvas still
                          // signs what you are owed.
                          balance.value < 0 ? -balance : balance,
                          signed: balance.value > 0,
                          tone: switch (balance.value) {
                            > 0 => MoneyTone.owedToYou,
                            < 0 => MoneyTone.youOwe,
                            _ => MoneyTone.settled,
                          },
                          size: 40,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              SizedBox(
                width: SettloSpacing.x2,
                height: largeText ? SettloSpacing.x2 : 0,
              ),
              MergeSemantics(
                child: Column(
                  crossAxisAlignment: largeText
                      ? CrossAxisAlignment.start
                      : CrossAxisAlignment.end,
                  children: [
                    Text(
                      monthName,
                      style: SettloTypography.footnote(color: c.textSecondary),
                    ),
                    const SizedBox(height: 4),
                    MoneyText(space.monthTotal, size: 17),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: SettloSpacing.x2),
          Semantics(
            label: 'Daily spend this month',
            excludeSemantics: true,
            child: CustomPaint(
              size: const Size.fromHeight(48),
              painter: _SparklinePainter(daily, c.textPrimary),
            ),
          ),
          Row(
            children: [
              Expanded(
                child: Text(
                  'Daily spend · ${monthName.substring(0, 3)}',
                  style: small,
                ),
              ),
              Text(
                '${formatInr(Paise(daily.last))} today',
                semanticsLabel: '${spokenInr(Paise(daily.last))} today',
                style: small,
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// [days] of spend as a line from the 1st to today, ending in a dot.
class _SparklinePainter extends CustomPainter {
  const new(this.days, this.color);

  final List<int> days;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final top = days.reduce(math.max);
    // The canvas draws between 12 and 36 of 48: room for the dot.
    Offset at(int i) => Offset(
      days.length == 1 ? size.width : size.width * i / (days.length - 1),
      size.height * (0.75 - 0.5 * (top == 0 ? 0 : days[i] / top)),
    );
    final path = Path()..moveTo(at(0).dx, at(0).dy);
    for (var i = 1; i < days.length; i++) {
      path.lineTo(at(i).dx, at(i).dy);
    }
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;
    canvas
      ..drawPath(path, paint)
      ..drawCircle(at(days.length - 1), 3.5, Paint()..color = color);
  }

  @override
  bool shouldRepaint(_SparklinePainter old) =>
      old.color != color || !_sameDays(old.days, days);

  static bool _sameDays(List<int> a, List<int> b) =>
      a.length == b.length && a.indexed.every((e) => b[e.$1] == e.$2);
}

/// Expenses, Balances and Activity. The track is drawn 40 high inside a
/// 44pt tap band, like [SSegmentedControl].
class _Tabs extends StatelessWidget {
  const new({required this.space, required this.tab});

  final SpaceSummary space;
  final SpaceTab tab;

  @override
  Widget build(BuildContext context) {
    final c = SettloColors.of(context);
    final tabs = [
      ('Expenses', SettloRoutes.space(space.id), tab == SpaceTab.expenses),
      (
        'Balances',
        SettloRoutes.spaceBalances(space.id),
        tab == SpaceTab.balances,
      ),
      (
        'Activity',
        SettloRoutes.spaceActivity(space.id),
        tab == SpaceTab.activity,
      ),
    ];
    return Stack(
      children: [
        Positioned.fill(
          top: 2,
          bottom: 2,
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: c.surface,
              borderRadius: BorderRadius.circular(SettloRadius.iconTile),
              border: Border.all(color: c.hairline),
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 3),
          child: Row(
            children: [
              for (final (label, route, selected) in tabs)
                Expanded(
                  child: SPressable(
                    selected: selected,
                    ringRadius: BorderRadius.circular(SettloRadius.compact),
                    onTap: () {
                      if (!selected) context.go(route);
                    },
                    child: SizedBox(
                      height: SettloSpacing.minTouchTarget,
                      child: Center(
                        child: Container(
                          height: 34,
                          alignment: Alignment.center,
                          decoration: BoxDecoration(
                            color: selected ? c.surfaceHighest : null,
                            borderRadius: BorderRadius.circular(
                              SettloRadius.compact,
                            ),
                          ),
                          padding: const EdgeInsets.symmetric(horizontal: 8),
                          child: FittedBox(
                            fit: BoxFit.scaleDown,
                            child: Text(
                              label,
                              maxLines: 1,
                              style: SettloTypography.subheadline(
                                weight: selected
                                    ? FontWeight.w500
                                    : FontWeight.w400,
                                color: selected
                                    ? c.textPrimary
                                    : c.textSecondary,
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ],
    );
  }
}

String _dayLabel(DateTime day, DateTime today) =>
    switch (today.difference(day).inDays) {
      0 => 'Today',
      1 => 'Yesterday',
      _ =>
        '${_weekdays[day.weekday - 1]} ${day.day} '
            '${_months[day.month - 1].substring(0, 3)}'
            '${day.year == today.year ? '' : ' ${day.year}'}',
    };

/// Expenses grouped by day, newest first, each led by its payer's avatar.
class _ExpenseList extends StatelessWidget {
  const new(this.space, this.ledger);

  final SpaceSummary space;
  final SpaceLedger ledger;

  @override
  Widget build(BuildContext context) {
    final c = SettloColors.of(context);
    final days = <DateTime, List<SpaceExpense>>{};
    for (final e in ledger.expenses) {
      (days[e.spentOn] ??= []).add(e);
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final (i, MapEntry(key: day, value: expenses))
            in days.entries.indexed) ...[
          Padding(
            padding: EdgeInsets.only(top: i == 0 ? 4 : 14, bottom: 4),
            child: Semantics(
              header: true,
              child: Text(
                _dayLabel(day, ledger.today),
                style: SettloTypography.footnote(color: c.textSecondary),
              ),
            ),
          ),
          for (final (j, e) in expenses.indexed)
            _ExpenseRow(space, e, divider: j < expenses.length - 1),
        ],
      ],
    );
  }
}

class _ExpenseRow extends StatelessWidget {
  const new(this.space, this.expense, {required this.divider});

  final SpaceSummary space;
  final SpaceExpense expense;
  final bool divider;

  @override
  Widget build(BuildContext context) {
    final c = SettloColors.of(context);
    final e = expense;
    final people = {
      for (final m in [...space.members, ...space.departed]) m.id: m,
    };
    final payer = e.payers.length == 1
        ? people[e.payers.single.memberId]
        : null;
    final paid = switch (payer) {
      SpaceMember(isYou: true) => 'you paid',
      final SpaceMember p => '${p.name} paid',
      null => '${e.payers.length} paid',
    };
    final payee = e.isSettlement && e.splits.length == 1
        ? people[e.splits.single.memberId]
        : null;
    // A pending or disputed settle-up does not count, so it says so and
    // its amount is grey (#78).
    final detail = switch (e.settlementStatus) {
      _ when !e.isSettlement =>
        e.splits.length == 1
            ? '$paid · for one'
            : '$paid · split ${e.splits.length} ways',
      SettlementStatus.pending when payee?.isYou ?? false =>
        'settle-up · confirm you received it',
      SettlementStatus.pending =>
        'settle-up · waiting for ${payee?.name ?? 'them'} to confirm',
      SettlementStatus.disputed when payee?.isYou ?? false =>
        "settle-up · you didn't receive it",
      SettlementStatus.disputed =>
        "settle-up · ${payee?.name ?? 'they'} didn't receive it",
      _ => 'settle-up',
    };
    final pending = e.settlementStatus == SettlementStatus.pending;
    final uncounted =
        pending || e.settlementStatus == SettlementStatus.disputed;
    final answerable = pending && (payee?.isYou ?? false);
    // Its creator or an owner may change it (docs/api.md), and only while
    // a settle-up is pending: answered ones are final. Nobody else sees
    // the action. The payee answers a pending one instead.
    final editable =
        !answerable &&
        (!e.isSettlement || pending) &&
        (e.createdByYou || space.you.isOwner);
    final row = Container(
      constraints: const BoxConstraints(
        minHeight: SettloSpacing.minTouchTarget,
      ),
      padding: const EdgeInsets.symmetric(vertical: SettloSpacing.x2),
      child: Row(
        children: [
          SAvatar(payer?.name ?? e.description, size: 36),
          const SizedBox(width: SettloSpacing.x2),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  e.description,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: SettloTypography.headline(color: c.textPrimary),
                ),
                const SizedBox(height: 3),
                Text(
                  detail,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: SettloTypography.footnote(color: c.textSecondary),
                ),
              ],
            ),
          ),
          const SizedBox(width: SettloSpacing.x1),
          MoneyText(
            e.amount,
            tone: uncounted ? MoneyTone.settled : MoneyTone.neutral,
          ),
        ],
      ),
    );
    if (answerable) {
      return MergeSemantics(
        child: Semantics(
          hint: 'Confirm or dispute',
          child: SPressable(
            onTap: () => showSAmountSheet<void>(
              context: context,
              builder: (_) => ConfirmSettlementSheet(
                space: space,
                expense: e,
                payer: payer?.name ?? 'They',
              ),
            ),
            child: row,
          ),
        ),
      );
    }
    if (!editable) return MergeSemantics(child: row);
    return MergeSemantics(
      child: Semantics(
        hint: 'Edit or delete',
        child: SPressable(
          onTap: () => showSAmountSheet<void>(
            context: context,
            builder: (_) => EditExpenseSheet(space: space, expense: e),
          ),
          child: row,
        ),
      ),
    );
  }
}

/// Who paid against their fair share this month: a bar of what each paid
/// and a tick at their agreed share, both scaled to the month's total
/// (canvas note n12). The tick is primary text, never gold, so the
/// meaning is its position, not a colour.
class _FairnessCard extends StatelessWidget {
  const new(this.space, this.ledger);

  final SpaceSummary space;
  final SpaceLedger ledger;

  @override
  Widget build(BuildContext context) {
    final c = SettloColors.of(context);
    final rows = [
      for (final m in [space.you, ...space.others, ...space.departed])
        if (ledger.fairness[m.id] case final f?) (m, f),
    ];
    final total = rows.fold(0, (s, r) => s + r.$2.fairShare.value);
    final shares = {for (final (_, f) in rows) f.fairShare};
    final month = _months[ledger.month.month - 1];
    final dark = Theme.of(context).brightness == Brightness.dark;
    final group = space.kind == SpaceKind.flat ? 'house' : 'space';
    return RepaintBoundary(
      key: fairnessCardKey,
      child: SCard(
        padding: const EdgeInsets.all(SettloSpacing.screenMargin),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    'WHO PAID VS FAIR SHARE · '
                    '${month.substring(0, 3).toUpperCase()}',
                    style: sectionLabel(c),
                  ),
                ),
                if (shares.length == 1 && rows.length > 1)
                  Text(
                    '${formatInr(shares.single)} EACH',
                    semanticsLabel: '${spokenInr(shares.single)} each',
                    style: sectionLabel(c),
                  ),
              ],
            ),
            const SizedBox(height: SettloSpacing.x2),
            if (total == 0)
              Text(
                'Nothing spent in $month yet.',
                style: SettloTypography.subheadline(color: c.textSecondary),
              )
            else ...[
              for (final (i, (m, f)) in rows.indexed)
                FairShareBar(
                  name: m.isYou ? 'You' : m.name,
                  paid: f.paid,
                  fairShare: f.fairShare,
                  monthTotal: Paise(total),
                  divider: i < rows.length - 1,
                ),
              const SizedBox(height: SettloSpacing.x2),
              Text(
                'The ${dark ? 'white' : 'dark'} tick is the fair share. A bar '
                'past it means that person '
                'carried the $group this month.',
                style: SettloTypography.footnote(color: c.textSecondary)
                    .copyWith(height: 1.5),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// One member's paid bar against the tick at their fair share, read aloud
/// as both amounts in rupees.
class FairShareBar extends StatelessWidget {
  /// [name] paid [paid] against [fairShare] of [monthTotal].
  const new({
    required this.name,
    required this.paid,
    required this.fairShare,
    required this.monthTotal,
    this.divider = false,
    super.key,
  });

  /// `You` or the member's name.
  final String name;

  /// What they paid this month.
  final Paise paid;

  /// Their agreed share of this month's spending.
  final Paise fairShare;

  /// The month's spending: the full width of the bar.
  final Paise monthTotal;

  /// Whether a hairline follows.
  final bool divider;

  /// The tick's key, for tests.
  static const Key tickKey = ValueKey('fair-share-tick');

  /// The paid bar's key, for tests.
  static const Key paidKey = ValueKey('fair-share-paid');

  @override
  Widget build(BuildContext context) {
    final c = SettloColors.of(context);
    final difference = paid - fairShare;
    final over = Paise(difference.value.abs());
    double share(Paise p) =>
        monthTotal.value == 0 ? 0 : (p.value / monthTotal.value).clamp(0, 1);
    final spoken =
        '$name paid ${spokenInr(paid)}, fair share ${spokenInr(fairShare)}, '
        '${switch (difference.value) {
          > 0 => '${spokenInr(over)} more than their share',
          < 0 => '${spokenInr(over)} less than their share',
          _ => 'exactly their share',
        }}';
    return Semantics(
      container: true,
      label: spoken,
      excludeSemantics: true,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: SettloSpacing.x2),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            SResponsiveRow(
              children: [
                Expanded(
                  child: Text(
                    name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: SettloTypography.body(color: c.textPrimary),
                  ),
                ),
                Text(
                  'paid ${formatInr(paid)} · ',
                  style: SettloTypography.amount(14, color: c.textSecondary),
                ),
                MoneyText(
                  difference,
                  size: 14,
                  signed: true,
                  // This is a share-of-spend delta, not outstanding debt.
                  tone: MoneyTone.settled,
                ),
              ],
            ),
            const SizedBox(height: 8),
            LayoutBuilder(
              builder: (context, box) => SizedBox(
                height: 8,
                child: Stack(
                  clipBehavior: Clip.none,
                  children: [
                    Positioned.fill(
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          color: c.surfaceHighest,
                          borderRadius: BorderRadius.circular(4),
                        ),
                      ),
                    ),
                    Positioned(
                      key: paidKey,
                      left: 0,
                      top: 0,
                      bottom: 0,
                      width: box.maxWidth * share(paid),
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          color: c.brandAccent,
                          borderRadius: BorderRadius.circular(4),
                        ),
                      ),
                    ),
                    Positioned(
                      key: tickKey,
                      left: (box.maxWidth * share(fairShare) - 1).clamp(
                        0,
                        box.maxWidth - 2,
                      ),
                      top: -4,
                      width: 2,
                      height: 16,
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          color: c.textPrimary,
                          borderRadius: BorderRadius.circular(1),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Balances simplified to the fewest payments (ADR 0003), with a way to
/// remind about or make each one that involves you, then the settle-ups you
/// paid that wait for their payee (#78), which are not offered again.
class _SettleCard extends StatelessWidget {
  const new(this.space);

  final SpaceSummary space;

  @override
  Widget build(BuildContext context) {
    final c = SettloColors.of(context);
    final payments = space.payments;
    final waiting = space.pendingFromYou;
    return SCard(
      padding: const EdgeInsets.all(SettloSpacing.screenMargin),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SResponsiveRow(
            children: [
              Expanded(
                child: Text('SIMPLEST WAY TO SETTLE', style: sectionLabel(c)),
              ),
              if (payments.isNotEmpty)
                Text(
                  payments.length == 1
                      ? '1 PAYMENT'
                      : '${payments.length} PAYMENTS',
                  style: sectionLabel(c),
                ),
            ],
          ),
          const SizedBox(height: SettloSpacing.x2),
          if (payments.isEmpty && waiting.isEmpty)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Text(
                'Everyone is settled up.',
                style: SettloTypography.subheadline(color: c.textSecondary),
              ),
            ),
          for (final (i, p) in payments.indexed)
            _PaymentRow(
              space,
              p,
              divider: i < payments.length - 1 || waiting.isNotEmpty,
            ),
          for (final (i, p) in waiting.indexed)
            _PaymentRow(
              space,
              p,
              divider: i < waiting.length - 1,
              waiting: true,
            ),
        ],
      ),
    );
  }
}

class _PaymentRow extends ConsumerWidget {
  const new(
    this.space,
    this.payment, {
    required this.divider,
    this.waiting = false,
  });

  final SpaceSummary space;
  final Payment<SpaceMember> payment;
  final bool divider;

  /// You paid it and the payee has not confirmed: grey, with no action.
  final bool waiting;

  /// A WhatsApp nudge to [from], who owes you; it records nothing.
  Future<void> _remind(
    BuildContext context,
    WidgetRef ref,
    SpaceMember from,
  ) async {
    final upi = space.you.upiId;
    final opened = await ref
        .read(openUrlProvider)(
          Uri.https('wa.me', '/${from.phone.replaceAll(RegExp(r'\D'), '')}', {
            'text':
                'Hi ${from.name}, a reminder about ${space.name}: you owe '
                '${formatInr(payment.amount)}. '
                '${upi == null ? '' : 'You can pay it to $upi on any UPI '
                          'app. '}'
                'Sent from SabkiJeb.',
          }),
        )
        .catchError((_) => false);
    if (!opened && context.mounted) {
      showSettloNotice(context, "Couldn't open WhatsApp");
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = SettloColors.of(context);
    final p = payment;
    final (other, label, action) = switch (p) {
      (:final to, from: _, amount: _) when waiting => (
        to,
        'Waiting for ${to.name} to confirm',
        null,
      ),
      (to: SpaceMember(isYou: true), :final from, amount: _) => (
        from,
        '${from.name} pays you',
        // An amount never goes to a number that hasn't verified; Spaces
        // offers them the invite instead.
        from.joined ? ('Remind', () => _remind(context, ref, from)) : null,
      ),
      (from: SpaceMember(isYou: true), :final to, amount: _) => (
        to,
        'You pay ${to.name}',
        ('Pay', () => context.push(SettloRoutes.settlePayTo(space.id, to.id))),
      ),
      (:final from, :final to, amount: _) => (
        from,
        '${from.name} pays ${to.name}',
        null,
      ),
    };
    return Container(
      constraints: const BoxConstraints(
        minHeight: SettloSpacing.minTouchTarget,
      ),
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: [
          SAvatar(other.name, size: 32),
          const SizedBox(width: SettloSpacing.x2),
          Expanded(
            child: MergeSemantics(
              child: Row(
                children: [
                  if (waiting) ...[
                    Icon(Icons.schedule, size: 16, color: c.pending),
                    const SizedBox(width: 6),
                  ],
                  Expanded(
                    child: Text(
                      label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: SettloTypography.body(
                        color: waiting ? c.pending : c.textPrimary,
                      ),
                    ),
                  ),
                  MoneyText(p.amount, color: waiting ? c.pending : null),
                ],
              ),
            ),
          ),
          // add_expense takes only active members, so nobody can settle
          // with someone who left.
          if (action case (final text, final onPressed)
              when space.members.contains(other)) ...[
            const SizedBox(width: SettloSpacing.x2),
            TextButton(
              onPressed: onPressed,
              style: TextButton.styleFrom(
                minimumSize: const Size.square(SettloSpacing.minTouchTarget),
                tapTargetSize: MaterialTapTargetSize.padded,
                padding: const EdgeInsets.symmetric(horizontal: 12),
                backgroundColor: c.action.withValues(alpha: 0.14),
                foregroundColor: c.action,
                shape: const StadiumBorder(),
                textStyle: SettloTypography.subheadline(),
              ),
              child: Text(text),
            ),
          ],
        ],
      ),
    );
  }
}

/// This month's spending by category, largest first.
class _CategoriesCard extends StatelessWidget {
  const new(this.ledger);

  final SpaceLedger ledger;

  @override
  Widget build(BuildContext context) {
    final c = SettloColors.of(context);
    final month = _months[ledger.month.month - 1].substring(0, 3);
    final rows = ledger.categories;
    return SCard(
      padding: const EdgeInsets.all(SettloSpacing.screenMargin),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text('BY CATEGORY · ${month.toUpperCase()}', style: sectionLabel(c)),
          const SizedBox(height: 4),
          for (final r in rows)
            MergeSemantics(
              child: Container(
                padding: const EdgeInsets.symmetric(vertical: SettloSpacing.x2),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        switch (r.category) {
                          null || '' => 'No category',
                          final s => s[0].toUpperCase() + s.substring(1),
                        },
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: SettloTypography.body(color: c.textPrimary),
                      ),
                    ),
                    Text(
                      r.count == 1 ? '1 expense · ' : '${r.count} expenses · ',
                      style: SettloTypography.footnote(color: c.textSecondary),
                    ),
                    MoneyText(r.total, size: 14),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// Paise from what was typed as rupees, `1,800` or `1800.5`; null when it
/// is not a positive amount.
Paise? parseRupees(String text) {
  final m = RegExp(r'^(\d+)(?:\.(\d{1,2}))?$')
      .firstMatch(text.replaceAll(',', '').trim());
  if (m == null) return null;
  final paise =
      int.parse(m[1]!) * 100 + int.parse((m[2] ?? '0').padRight(2, '0'));
  return paise > 0 ? Paise(paise) : null;
}

/// Edit or delete an expense. Only an equal split with one payer can
/// change its amount here: any other split has amounts per person that
/// would all need choosing again.
///
/// Each action's idempotency key is made once when the sheet opens and
/// sent with every attempt, so a retry never applies a change twice.
class EditExpenseSheet extends ConsumerStatefulWidget {
  /// The sheet for [expense] in [space].
  const new({required this.space, required this.expense, super.key});

  /// The space it belongs to.
  final SpaceSummary space;

  /// The expense changed.
  final SpaceExpense expense;

  @override
  ConsumerState<EditExpenseSheet> createState() => _EditExpenseSheetState();
}

class _EditExpenseSheetState extends ConsumerState<EditExpenseSheet> {
  final String _editKey = newIdempotencyKey();
  final String _deleteKey = newIdempotencyKey();
  late final _amount = TextEditingController(
    text: formatInr(widget.expense.amount).substring(1),
  );
  late final _description = TextEditingController(
    text: widget.expense.description,
  );
  bool _confirmDelete = false;
  bool _saving = false;
  String? _error;

  bool get _amountEditable =>
      widget.expense.splitType == 'equal' && widget.expense.payers.length == 1;

  @override
  void dispose() {
    _amount.dispose();
    _description.dispose();
    super.dispose();
  }

  Future<void> _run(Future<void> Function(SpaceLedgerController) write) async {
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await write(ref.read(spaceLedgerProvider(widget.space.id).notifier));
      if (mounted) Navigator.of(context).pop();
    } on IdempotencyConflict {
      _error =
          'This change was already saved with what you first entered. '
          'Close this to see it.';
    } on SessionEnded {
      // Signed out mid-tap: the user has left, so there is nothing to say.
    } on Exception {
      _error = "We couldn't save that. Check your connection and try again.";
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _save() async {
    final e = widget.expense;
    final amount = _amountEditable ? parseRupees(_amount.text) : e.amount;
    final description = _description.text.trim();
    if (amount == null || description.isEmpty) {
      setState(
        () => _error = amount == null
            ? 'Enter an amount, like 1,800'
            : 'Say what it was for',
      );
      return;
    }
    await _run(
      (ledger) => ledger.edit((
        id: e.id,
        description: description,
        category: e.category,
        amount: amount,
        spentOn: e.spentOn,
        isSettlement: e.isSettlement,
        splitType: e.splitType,
        payers: _amountEditable
            ? [(memberId: e.payers.single.memberId, amount: amount)]
            : e.payers,
        splits: e.splits,
      ), idempotencyKey: _editKey),
    );
  }

  Future<void> _delete() async {
    if (Theme.of(context).platform == TargetPlatform.iOS) {
      final delete = await showSettloActionSheet(
        context: context,
        message: 'This expense will be deleted for everyone in the space.',
        destructive: 'Delete Expense',
        cancel: 'Cancel',
      );
      if (delete != true || !mounted) return;
    } else if (!_confirmDelete) {
      setState(() => _confirmDelete = true);
      return;
    }
    await _run(
      (ledger) => ledger.delete(widget.expense.id, idempotencyKey: _deleteKey),
    );
  }

  @override
  Widget build(BuildContext context) {
    final c = SettloColors.of(context);
    final text = Theme.of(context).textTheme;
    return SAmountSheet(
      title: 'Edit expense · ${widget.space.name}',
      onClose: () => Navigator.of(context).pop(),
      dirty:
          _amount.text != formatInr(widget.expense.amount).substring(1) ||
          _description.text != widget.expense.description,
      saving: _saving,
      amount: _amountEditable
          ? IntrinsicWidth(
              child: TextField(
                controller: _amount,
                onChanged: (_) => setState(() {}),
                enabled: !_saving,
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                ),
                style: DefaultTextStyle.of(context).style,
                decoration: const InputDecoration(
                  isDense: true,
                  border: InputBorder.none,
                  filled: false,
                  contentPadding: EdgeInsets.zero,
                ),
              ),
            )
          : Text(formatInr(widget.expense.amount).substring(1)),
      body: SFormBody(
        children: [
          TextField(
            controller: _description,
            onChanged: (_) => setState(() {}),
            enabled: !_saving,
            textCapitalization: TextCapitalization.sentences,
            decoration: const InputDecoration(labelText: 'What was it for'),
          ),
          if (!_amountEditable) ...[
            const SizedBox(height: SettloSpacing.x1),
            Text(
              'This expense is split by amount per person, so its amount '
              'stays as it is. Delete it and add it again to change it.',
              style: text.bodySmall?.copyWith(color: c.textSecondary),
            ),
          ],
          if (_error case final error?) ...[
            const SizedBox(height: SettloSpacing.x2),
            Text(error, style: SettloTypography.subheadline(color: c.error)),
          ],
          const SizedBox(height: SettloSpacing.x2),
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton(
              onPressed: _saving ? null : _delete,
              style: TextButton.styleFrom(
                minimumSize: const Size(0, SettloSpacing.minTouchTarget),
                foregroundColor: c.textPrimary,
              ),
              child: Text(
                _confirmDelete ? 'Tap again to delete' : 'Delete expense',
              ),
            ),
          ),
        ],
      ),
      action: SPrimaryButton(
        label: 'Save changes',
        onPressed: _saving ? null : _save,
      ),
    );
  }
}

/// The payee's answer to a pending settle-up, as on ConfirmRepayment:
/// confirm it arrived, or say it didn't with a reason. Both are final.
/// Each answer's idempotency key is made once when the sheet opens.
class ConfirmSettlementSheet extends ConsumerStatefulWidget {
  /// The sheet for settle-up [expense] in [space], paid by [payer].
  const new({
    required this.space,
    required this.expense,
    required this.payer,
    super.key,
  });

  /// The space it belongs to.
  final SpaceSummary space;

  /// The pending settle-up; you are its payee.
  final SpaceExpense expense;

  /// The payer's name.
  final String payer;

  @override
  ConsumerState<ConfirmSettlementSheet> createState() =>
      _ConfirmSettlementSheetState();
}

class _ConfirmSettlementSheetState
    extends ConsumerState<ConfirmSettlementSheet> {
  final String _confirmKey = newIdempotencyKey();
  final String _disputeKey = newIdempotencyKey();
  final _reason = TextEditingController();

  /// Asking why, before disputing.
  bool _disputing = false;
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _reason.dispose();
    super.dispose();
  }

  Future<void> _run(Future<void> Function(SpaceLedgerController) write) async {
    // The buttons disable only on the next frame; a second tap in this one
    // must not answer (or pop) again.
    if (_busy) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await write(ref.read(spaceLedgerProvider(widget.space.id).notifier));
      if (mounted) Navigator.of(context).pop();
      // Done: stay busy, so a tap still queued on this frame is dropped.
      return;
    } on IdempotencyConflict {
      _error = 'You already answered this. Close this to see it.';
    } on SettlementChanged {
      ref.read(ledgerRevisionProvider.notifier).bump();
      _error =
          'This settle-up was just changed. Close this and check it again.';
    } on SessionEnded {
      // Signed out mid-tap: the user has left, so there is nothing to say.
    } on Exception {
      _error =
          "We couldn't save that. Check your connection and try again. "
          "It won't be saved twice.";
    }
    if (mounted) setState(() => _busy = false);
  }

  Future<void> _confirm() => _run(
    (ledger) =>
        ledger.confirmSettlement(widget.expense, idempotencyKey: _confirmKey),
  );

  Future<void> _dispute() async {
    final reason = _reason.text.trim();
    if (reason.isEmpty) {
      setState(() => _error = 'Say what went wrong, like "Not in my account"');
      return;
    }
    await _run(
      (ledger) => ledger.disputeSettlement(
        widget.expense.id,
        reason,
        idempotencyKey: _disputeKey,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final c = SettloColors.of(context);
    final amount = formatInr(widget.expense.amount);
    return SAmountSheet(
      title: 'Confirm settle-up · ${widget.space.name}',
      onClose: () => Navigator.of(context).pop(),
      dirty: _disputing && _reason.text.isNotEmpty,
      saving: _busy,
      amountLabel: '${widget.payer} says they paid you',
      amount: Semantics(
        label: spokenInr(widget.expense.amount),
        excludeSemantics: true,
        child: Text(amount.substring(1)),
      ),
      body: SFormBody(
        children: [
          Text(
            _disputing
                ? 'It stays in the space, marked as not received, and '
                      "doesn't count. ${widget.payer} can record it again."
                : 'Check your bank or UPI app for $amount from '
                      '${widget.payer} before confirming. Confirming is '
                      'final and updates both ledgers.',
            textAlign: TextAlign.center,
            style: SettloTypography.subheadline(color: c.textSecondary),
          ),
          if (_disputing) ...[
            const SizedBox(height: SettloSpacing.x2),
            TextField(
              controller: _reason,
              enabled: !_busy,
              onChanged: (_) => setState(() {}),
              maxLength: 500,
              textCapitalization: TextCapitalization.sentences,
              decoration: const InputDecoration(labelText: 'What went wrong'),
            ),
          ],
          if (_error case final error?) ...[
            const SizedBox(height: SettloSpacing.x2),
            Text(
              error,
              textAlign: TextAlign.center,
              style: SettloTypography.subheadline(color: c.error),
            ),
          ],
        ],
      ),
      action: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: _disputing
            ? [
                SPrimaryButton(
                  label: _busy ? 'Saving…' : 'Mark as not received',
                  onPressed: _busy ? null : _dispute,
                ),
                const SizedBox(height: SettloSpacing.x2),
                SSecondaryButton(
                  label: 'Back',
                  onPressed: _busy
                      ? null
                      : () => setState(() {
                          _disputing = false;
                          _error = null;
                        }),
                ),
              ]
            : [
                SPrimaryButton(
                  label: _busy ? 'Saving…' : 'Yes, I received $amount',
                  onPressed: _busy ? null : _confirm,
                ),
                const SizedBox(height: SettloSpacing.x2),
                SSecondaryButton(
                  label: "I didn't receive this",
                  onPressed: _busy
                      ? null
                      : () => setState(() {
                          _disputing = true;
                          _error = null;
                        }),
                ),
              ],
      ),
    );
  }
}
