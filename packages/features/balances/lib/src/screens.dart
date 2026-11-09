import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:settlo_balances/src/home_controller.dart';
import 'package:settlo_balances/src/widgets.dart';
import 'package:settlo_core/settlo_core.dart';

/// Home (Main, HomeEmpty, HomeFound and HomeLight artboards).
///
/// Three states share one layout so nothing jumps when data arrives: the
/// net position card sits under the header in all of them (canvas notes
/// n03, n40, n41). With claims to review the claims come first and the
/// balances stay blank until each is accepted or rejected.
class HomeScreen extends ConsumerWidget {
  /// The Home tab.
  const new({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final home = ref.watch(homeProvider);
    final data = home.value;
    final media = MediaQuery.of(context);
    const gap = SizedBox(height: 14);
    // The canvas sets letter spacing and line height only where it means
    // to; elsewhere they are 0 and CSS `normal` (1.2 for Figtree).
    return Scaffold(
      body: DefaultTextStyle.merge(
        style: const TextStyle(letterSpacing: 0, height: 1.2),
        child: RefreshIndicator(
          onRefresh: () => ref.refresh(homeProvider.future),
          child: ListView(
            padding: EdgeInsets.fromLTRB(
              SettloSpacing.screenMargin,
              math.max(media.padding.top, 44) + 16,
              SettloSpacing.screenMargin,
              media.padding.bottom + SettloSpacing.x2,
            ),
            children: [
              _Header(name: data?.name ?? ''),
              const SizedBox(height: SettloSpacing.x3),
              ...switch (data) {
                null => [
                  _NetCard.muted(
                    caption: home.hasError
                        ? "We couldn't load your balances. Pull down to try "
                              'again.'
                        : '',
                  ),
                ],
                HomeData(isEmpty: true) => const [
                  _NetCard.muted(
                    caption:
                        'Nothing recorded yet. Your first entry takes about '
                        'ten seconds.',
                  ),
                  gap,
                  _JobTile(
                    icon: _SpaceIcon(SpaceKind.flat, tile: false),
                    title: 'Start a space',
                    body:
                        'Flatmates, a trip, or one friend. Add people by '
                        "phone number — they don't need the app yet.",
                    route: SettloRoutes.spaces,
                  ),
                  SizedBox(height: 12),
                  _JobTile(
                    icon: _LoanIcon(),
                    title: 'Record a loan',
                    body:
                        'Money you lent or borrowed. Both of you see every '
                        'repayment and confirm it.',
                    route: SettloRoutes.newLoan,
                  ),
                  SizedBox(height: 12),
                  _ContactsNote(),
                ],
                HomeData(claims: [_, ...]) => [
                  _ClaimsCard(data),
                  gap,
                  const _NetCard.blank(),
                  gap,
                  const _Note(),
                  ..._balances(data),
                ],
                _ => [_NetCard(data), gap, _Actions(), ..._balances(data)],
              },
            ],
          ),
        ),
      ),
    );
  }

  static List<Widget> _balances(HomeData data) => [
    if (data.spaces.isNotEmpty) ...[
      const SizedBox(height: 20),
      _SpacesCard(data.spaces),
    ],
    if (data.loans.isNotEmpty) ...[
      const SizedBox(height: 12),
      _LoansCard(data.loans),
    ],
  ];
}

const _months = [
  'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', //
  'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
];

String _count(int n, String noun) => '$n $noun${n == 1 ? '' : 's'}';

/// `2 spaces and 1 loan`, leaving out a part that is zero.
String _spacesAndLoans(int spaces, int loans) => [
  if (spaces > 0) _count(spaces, 'space'),
  if (loans > 0) _count(loans, 'loan'),
].join(' and ');

/// An Indian mobile number grouped as on the canvas, `+91 98765 43210`.
String _groupPhone(String e164) => e164.startsWith('+91') && e164.length == 13
    ? '+91 ${e164.substring(3, 8)} ${e164.substring(8)}'
    : e164;

class _Header extends StatelessWidget {
  const new({required this.name});

  final String name;

  @override
  Widget build(BuildContext context) {
    final c = SettloColors.of(context);
    return Row(
      children: [
        Semantics(
          label: 'Settlo',
          excludeSemantics: true,
          child: Row(
            children: [
              Container(
                width: 26,
                height: 26,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: c.action,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: HomeIcon(
                  HomeGlyph.mark,
                  color: c.onAction,
                  size: 13,
                  stroke: 3.2,
                ),
              ),
              const SizedBox(width: SettloSpacing.x1),
              Text(
                'settlo',
                style: SettloTypography.figtree(
                  22,
                  weight: FontWeight.w500,
                  letterSpacing: -0.6,
                  color: c.textPrimary,
                ),
              ),
            ],
          ),
        ),
        const Spacer(),
        IconButton(
          tooltip: 'Notifications',
          onPressed: () => context.go(SettloRoutes.activity),
          style: IconButton.styleFrom(
            fixedSize: const Size.square(SettloSpacing.minTouchTarget),
            minimumSize: Size.zero,
            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
            backgroundColor: c.surface,
            side: BorderSide(color: c.hairline),
          ),
          icon: HomeIcon(HomeGlyph.bell, color: c.textPrimary, size: 22),
        ),
        const SizedBox(width: SettloSpacing.x1),
        // Neutral, as every avatar is; the canvas's gold avatar waits on
        // the owner's decision.
        Semantics(
          button: true,
          label: 'Profile',
          excludeSemantics: true,
          child: InkWell(
            customBorder: const CircleBorder(),
            onTap: () => context.go(SettloRoutes.profile),
            child: SAvatar(name, size: SettloSpacing.minTouchTarget),
          ),
        ),
      ],
    );
  }
}

TextStyle _label(SettloColors c) =>
    SettloTypography.figtree(12, letterSpacing: 0.3, color: c.textSecondary);

TextStyle _caption(SettloColors c) =>
    SettloTypography.figtree(13, color: c.textSecondary);

/// The hero: net position, with owed / owe / month spend when known.
class _NetCard extends StatelessWidget {
  const new(HomeData this.data)
    : label = 'NET POSITION',
      caption = null,
      blank = false;

  /// ₹0 in muted type: nothing recorded yet, or still loading.
  const new muted({required this.caption})
    : data = null,
      label = 'NET POSITION',
      blank = false;

  /// ₹— while claims wait for review.
  const new blank()
    : data = null,
      label = 'NET POSITION · AFTER YOU REVIEW',
      caption = 'Balances appear once you accept or dispute each item above.',
      blank = true;

  final HomeData? data;
  final String label;
  final String? caption;
  final bool blank;

  @override
  Widget build(BuildContext context) {
    final c = SettloColors.of(context);
    final data = this.data;
    final String caption;
    final Widget amount;
    if (data == null) {
      caption = this.caption!;
      amount = blank
          ? const MoneyText.blank(size: 46)
          : const MoneyText(Paise.zero, tone: MoneyTone.settled, size: 46);
    } else {
      final net = data.net.value;
      final where = _spacesAndLoans(data.spaces.length, data.loans.length);
      caption = net > 0
          ? 'owed to you across $where'
          : net < 0
          ? 'you owe across $where'
          : 'all settled across $where';
      amount = MoneyText(data.net, size: 46, signed: true);
    }
    return SCard(
      hero: true,
      padding: const EdgeInsets.all(22),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: _label(c)),
          const SizedBox(height: SettloSpacing.x1),
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: amount,
          ),
          if (caption.isNotEmpty) ...[
            const SizedBox(height: 6),
            Text(caption, style: _caption(c)),
          ],
          if (data != null) ...[
            const SizedBox(height: 22),
            Divider(height: 1, thickness: 1, color: c.hairline),
            const SizedBox(height: 18),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _Stat(
                  'You are owed',
                  data.owed,
                  data.owed.value > 0 ? MoneyTone.owedToYou : MoneyTone.settled,
                ),
                const SizedBox(width: SettloSpacing.x3),
                _Stat(
                  'You owe',
                  data.owe,
                  data.owe.value > 0 ? MoneyTone.youOwe : MoneyTone.settled,
                ),
                const Spacer(),
                _Stat(
                  '${_months[data.month.month - 1]} spend',
                  data.monthSpend,
                  MoneyTone.neutral,
                  end: true,
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

class _Stat extends StatelessWidget {
  const new(this.label, this.amount, this.tone, {this.end = false});

  final String label;
  final Paise amount;
  final MoneyTone tone;
  final bool end;

  @override
  Widget build(BuildContext context) => MergeSemantics(
    child: Column(
      crossAxisAlignment: end
          ? CrossAxisAlignment.end
          : CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: SettloTypography.figtree(
            12,
            color: SettloColors.of(context).textSecondary,
          ),
        ),
        const SizedBox(height: 2),
        MoneyText(amount, tone: tone, size: 17),
      ],
    ),
  );
}

class _Actions extends StatelessWidget {
  @override
  Widget build(BuildContext context) => Row(
    children: [
      Expanded(
        child: SPrimaryButton(
          label: 'Add expense',
          icon: HomeIcon(
            HomeGlyph.plus,
            color: SettloColors.of(context).onAction,
            size: 18,
            stroke: 1.9,
          ),
          onPressed: () => context.push(SettloRoutes.addExpense),
        ),
      ),
      const SizedBox(width: 10),
      Expanded(
        child: SSecondaryButton(
          label: 'Settle up',
          onPressed: () => context.push(SettloRoutes.settle),
        ),
      ),
    ],
  );
}

/// A card titled [title] with an optional trailing link.
class _Section extends StatelessWidget {
  const new({
    required this.title,
    required this.children,
    this.bottom = 6,
    this.action,
  });

  final String title;
  final List<Widget> children;
  final double bottom;
  final (String, String)? action;

  @override
  Widget build(BuildContext context) {
    final c = SettloColors.of(context);
    final card = SCard(
      padding: EdgeInsets.fromLTRB(20, 18, 20, bottom),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(title, style: _label(c)),
          const SizedBox(height: 10),
          ...children,
        ],
      ),
    );
    final action = this.action;
    if (action == null) return card;
    final (label, route) = action;
    // The link is drawn where the canvas puts it (19 from the top, 21 from
    // the right, counting the 1px edge) inside a 44pt-tall target that
    // covers the card's corner, so the larger target moves nothing.
    return Stack(
      children: [
        card,
        Positioned(
          top: 0,
          right: 0,
          child: Semantics(
            button: true,
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: () => context.go(route),
              child: Container(
                constraints: const BoxConstraints(
                  minHeight: SettloSpacing.minTouchTarget,
                ),
                padding: const EdgeInsets.fromLTRB(12, 19, 21, 0),
                child: Text(label, style: _label(c)),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

/// A list row: [leading], a title over a detail line, then [trailing].
class _Row extends StatelessWidget {
  const new({
    required this.leading,
    required this.title,
    required this.detail,
    this.detailSpoken,
    this.trailing,
    this.onTap,
    this.divider = false,
    this.padding = const EdgeInsets.symmetric(vertical: 14),
  });

  final Widget leading;
  final String title;
  final String detail;

  /// What a screen reader says for [detail] when it holds an amount.
  final String? detailSpoken;
  final Widget? trailing;
  final VoidCallback? onTap;
  final bool divider;
  final EdgeInsets padding;

  @override
  Widget build(BuildContext context) {
    final c = SettloColors.of(context);
    final trailing = this.trailing;
    return MergeSemantics(
      child: InkWell(
        onTap: onTap,
        child: Container(
          constraints: const BoxConstraints(
            minHeight: SettloSpacing.minTouchTarget,
          ),
          padding: padding,
          decoration: divider
              ? BoxDecoration(
                  border: Border(bottom: BorderSide(color: c.hairline)),
                )
              : null,
          child: Row(
            children: [
              leading,
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: SettloTypography.figtree(15, color: c.textPrimary),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      detail,
                      semanticsLabel: detailSpoken,
                      style: SettloTypography.figtree(
                        12,
                        color: c.textSecondary,
                      ).copyWith(height: 1.3),
                    ),
                  ],
                ),
              ),
              if (trailing != null) ...[
                const SizedBox(width: SettloSpacing.x1),
                trailing,
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _SpaceIcon extends StatelessWidget {
  const new(this.kind, {this.tile = true});

  final SpaceKind kind;

  /// In a 40px list tile in primary text; otherwise bare, for a job tile.
  final bool tile;

  @override
  Widget build(BuildContext context) {
    final c = SettloColors.of(context);
    final color = tile ? c.textPrimary : c.action;
    final glyph = switch (kind) {
      SpaceKind.flat => STabIcon.home.widget,
      SpaceKind.trip => HomeIcon(HomeGlyph.plane, color: color),
      SpaceKind.friend => HomeIcon(HomeGlyph.person, color: color),
      SpaceKind.other => STabIcon.spaces.widget,
    };
    final icon = IconTheme(
      data: IconThemeData(color: color, size: tile ? 20 : 22),
      child: glyph,
    );
    if (!tile) return icon;
    return Container(
      width: 40,
      height: 40,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: c.surfaceRaised,
        borderRadius: BorderRadius.circular(SettloRadius.iconTile),
      ),
      child: icon,
    );
  }
}

class _LoanIcon extends StatelessWidget {
  const new();

  @override
  Widget build(BuildContext context) => IconTheme(
    data: IconThemeData(color: SettloColors.of(context).action, size: 22),
    child: STabIcon.loans.widget,
  );
}

class _SpacesCard extends StatelessWidget {
  const new(this.spaces);

  final List<HomeSpace> spaces;

  @override
  Widget build(BuildContext context) => _Section(
    title: 'SPACES',
    action: ('SEE ALL', SettloRoutes.spaces),
    children: [
      for (final (i, s) in spaces.indexed)
        _Row(
          leading: _SpaceIcon(s.kind),
          title: s.name,
          detail: switch (s.people) {
            [] => 'Just you',
            [_] || [_, _] => s.people.join(', '),
            _ => '${s.people.length + 1} people',
          },
          trailing: MoneyText(
            s.balance,
            signed: true,
            tone: switch (s.balance.value) {
              > 0 => MoneyTone.owedToYou,
              < 0 => MoneyTone.youOwe,
              _ => MoneyTone.settled,
            },
          ),
          divider: i < spaces.length - 1,
          onTap: () => context.go(SettloRoutes.space(s.id)),
        ),
    ],
  );
}

class _LoansCard extends StatelessWidget {
  const new(this.loans);

  final List<HomeLoan> loans;

  @override
  Widget build(BuildContext context) {
    final c = SettloColors.of(context);
    return _Section(
      title: 'LOANS',
      bottom: 20,
      children: [
        for (final (i, l) in loans.indexed) ...[
          if (i > 0) const SizedBox(height: SettloSpacing.x3),
          _Row(
            padding: EdgeInsets.zero,
            leading: SAvatar(l.counterparty),
            title: '${l.counterparty} · interest free',
            detail: _detail(l, formatInr),
            detailSpoken: _detail(l, spokenInr),
            trailing: MoneyText(l.outstanding),
            onTap: () => context.go(SettloRoutes.loans),
          ),
          if (l
              case HomeLoan(
                installmentsPaid: final paid?,
                installmentsTotal: final total?,
              )
              when total > 0)
            Padding(
              padding: const EdgeInsets.only(top: 14),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(2),
                child: LinearProgressIndicator(
                  value: paid / total,
                  minHeight: 4,
                  backgroundColor: c.surfaceHighest,
                  color: c.textPrimary,
                ),
              ),
            ),
        ],
      ],
    );
  }

  /// [money] writes the instalment: [formatInr] to show, [spokenInr] to
  /// read.
  static String _detail(HomeLoan l, String Function(Paise) money) {
    final side = l.youLent ? 'you lent' : 'you borrowed';
    final (paid, total) = (l.installmentsPaid, l.installmentsTotal);
    if (paid == null || total == null) return '$side · flexible repayments';
    final next = l.nextDueOn;
    final installment = l.installment;
    if (next == null || installment == null) return '$paid of $total';
    return '$paid of $total · next ${money(installment)} on '
        '${next.day} ${_months[next.month - 1]}';
  }
}

class _JobTile extends StatelessWidget {
  const new({
    required this.icon,
    required this.title,
    required this.body,
    required this.route,
  });

  final Widget icon;
  final String title;
  final String body;
  final String route;

  @override
  Widget build(BuildContext context) {
    final c = SettloColors.of(context);
    return Semantics(
      button: true,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () => context.push(route),
        child: SCard(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 44,
                height: 44,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: c.action.withValues(alpha: 0.14),
                  borderRadius: BorderRadius.circular(SettloRadius.button),
                ),
                child: icon,
              ),
              const SizedBox(height: SettloSpacing.x2),
              Text(
                title,
                style: SettloTypography.figtree(
                  17,
                  weight: FontWeight.w500,
                  letterSpacing: -0.2,
                  color: c.textPrimary,
                ),
              ),
              const SizedBox(height: 6),
              Text(body, style: _caption(c).copyWith(height: 1.5)),
              const SizedBox(height: 14),
              Row(
                children: [
                  Text(
                    'Start',
                    style: SettloTypography.figtree(
                      13,
                      weight: FontWeight.w500,
                      color: c.action,
                    ),
                  ),
                  const SizedBox(width: 6),
                  HomeIcon(HomeGlyph.arrow, color: c.action, size: 16),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ContactsNote extends StatelessWidget {
  const new();

  @override
  Widget build(BuildContext context) {
    final c = SettloColors.of(context);
    return SCard(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      child: Row(
        children: [
          HomeIcon(HomeGlyph.person, color: c.textSecondary),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              'Find friends already on Settlo. We match hashed numbers only; '
              'your contact list never leaves your phone.',
              style: _caption(c).copyWith(height: 1.5),
            ),
          ),
          const SizedBox(width: 12),
          _TextAction(
            'Allow',
            color: c.action,
            alignment: Alignment.centerRight,
            onTap: () => context.go(SettloRoutes.profile),
          ),
        ],
      ),
    );
  }
}

/// A text-only action with a target of at least 44x44pt.
class _TextAction extends StatelessWidget {
  const new(
    this.label, {
    required this.color,
    required this.onTap,
    this.alignment = Alignment.centerLeft,
  });

  final String label;
  final Color color;
  final VoidCallback onTap;

  /// Where a label shorter than the target sits inside it.
  final AlignmentGeometry alignment;

  @override
  Widget build(BuildContext context) => TextButton(
    onPressed: onTap,
    style: TextButton.styleFrom(
      foregroundColor: color,
      alignment: alignment,
      minimumSize: const Size.square(SettloSpacing.minTouchTarget),
      padding: EdgeInsets.zero,
      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
      textStyle: SettloTypography.figtree(13, weight: FontWeight.w500),
    ),
    child: Text(label),
  );
}

/// Everything recorded against the number before it was verified, as
/// claims: someone's word, not facts (canvas note n41).
class _ClaimsCard extends StatelessWidget {
  const new(this.data);

  final HomeData data;

  @override
  Widget build(BuildContext context) {
    final c = SettloColors.of(context);
    final claims = data.claims;
    final what = _spacesAndLoans(
      claims.where((x) => x.kind == ClaimKind.spaceMember).length,
      claims.where((x) => x.kind == ClaimKind.loan).length,
    );
    return SCard(
      hero: true,
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // A tick is status, so it is neutral, never gold.
              Container(
                width: 40,
                height: 40,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: c.surfaceHighest,
                  borderRadius: BorderRadius.circular(SettloRadius.iconTile),
                ),
                child: HomeIcon(
                  HomeGlyph.check,
                  color: c.textPrimary,
                  stroke: 2.2,
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Your ledger was waiting',
                      style: SettloTypography.figtree(
                        16,
                        weight: FontWeight.w500,
                        letterSpacing: -0.2,
                        color: c.textPrimary,
                      ),
                    ),
                    const SizedBox(height: SettloSpacing.half),
                    Text(
                      'Friends recorded $what against '
                      '${_groupPhone(data.phone)} before you joined. Review '
                      'them — nothing is confirmed until you say so.',
                      style: _caption(c).copyWith(height: 1.5),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: SettloSpacing.x2),
          Divider(height: 1, thickness: 1, color: c.hairline),
          const SizedBox(height: 6),
          for (final (i, claim) in claims.indexed)
            _ClaimRow(claim, divider: i < claims.length - 1),
        ],
      ),
    );
  }
}

class _ClaimRow extends ConsumerWidget {
  const new(this.claim, {required this.divider});

  final Claim claim;
  final bool divider;

  /// `Rahul says you owe ₹750 · 3 people`: their word, in their name.
  /// [money] writes the amount: [formatInr] to show, [spokenInr] to read.
  String _says(String Function(Paise) money) {
    final who = claim.recordedBy;
    final amount = money(Paise(claim.amount.value.abs()));
    return switch (claim) {
      Claim(kind: ClaimKind.loan, youLent: true) =>
        '$who says you lent $amount',
      Claim(kind: ClaimKind.loan) => '$who says you borrowed $amount',
      Claim(amount: Paise(value: > 0)) =>
        '$who says you are owed $amount · ${claim.people} people',
      Claim(amount: Paise(value: < 0)) =>
        '$who says you owe $amount · ${claim.people} people',
      _ => '$who says you are in this space · ${claim.people} people',
    };
  }

  Future<void> _settle(
    BuildContext context,
    WidgetRef ref,
    Future<void> Function(HomeController) call,
  ) async {
    final messenger = ScaffoldMessenger.of(context);
    try {
      await call(ref.read(homeProvider.notifier));
    } on Exception {
      messenger.showSnackBar(
        const SnackBar(
          content: Text(
            "We couldn't save that. Check your connection and try again.",
          ),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = SettloColors.of(context);
    return Container(
      padding: const EdgeInsets.only(top: 14, bottom: SettloSpacing.half),
      decoration: divider
          ? BoxDecoration(
              border: Border(bottom: BorderSide(color: c.hairline)),
            )
          : null,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SAvatar(claim.recordedBy, size: 36),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  claim.kind == ClaimKind.loan
                      ? 'Loan with ${claim.title}'
                      : claim.title,
                  style: SettloTypography.figtree(15, color: c.textPrimary),
                ),
                const SizedBox(height: 3),
                Text(
                  _says(formatInr),
                  semanticsLabel: _says(spokenInr),
                  style: SettloTypography.figtree(
                    12,
                    color: c.textSecondary,
                  ).copyWith(height: 1.3),
                ),
                Row(
                  children: [
                    _TextAction(
                      'Accept',
                      color: c.action,
                      onTap: () =>
                          _settle(context, ref, (h) => h.accept(claim)),
                    ),
                    const SizedBox(width: SettloSpacing.x3),
                    _TextAction(
                      "This isn't me",
                      color: c.textSecondary,
                      onTap: () =>
                          _settle(context, ref, (h) => h.reject(claim)),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _Note extends StatelessWidget {
  const new();

  @override
  Widget build(BuildContext context) {
    final c = SettloColors.of(context);
    return SCard(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          HomeIcon(HomeGlyph.shield, color: c.textSecondary),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              'Why you are seeing this now and not earlier: Settlo only '
              'reveals what is attached to a number after the number is '
              'verified.',
              style: _caption(c).copyWith(height: 1.5),
            ),
          ),
        ],
      ),
    );
  }
}
