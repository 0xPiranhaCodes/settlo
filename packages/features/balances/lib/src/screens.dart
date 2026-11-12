import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:settlo_activity/settlo_activity.dart';
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
    const gap = SizedBox(height: SettloSpacing.x3);
    // The canvas sets letter spacing and line height only where it means
    // to; elsewhere they are 0 and CSS `normal` (1.2 for Figtree).
    final c = SettloColors.of(context);
    return Scaffold(
      body: Stack(
        children: [
          Positioned.fill(
            child: ExcludeSemantics(
              child: CustomPaint(
                painter: WelcomeBackgroundPainter(
                  background: c.background,
                  gold: c.homeGold,
                  highlight: c.homeGold,
                  placement: SettloArcPlacement.home,
                ),
              ),
            ),
          ),
          DefaultTextStyle.merge(
            style: const TextStyle(letterSpacing: 0, height: 1.2),
            child: SettloScrollScaffold(
              title: 'SETTLO',
              stickyHeader: false,
              onRefresh: () => _refresh(ref),
              padding: EdgeInsets.fromLTRB(
                SettloSpacing.screenMargin,
                math.max(media.padding.top, 44) + 16,
                SettloSpacing.screenMargin,
                media.padding.bottom + SettloSpacing.x2,
              ),
              children: [
                _Header(data?.name),
                // The shared header already reserves the mock's 24px gap.
                ...switch (data) {
                  null => [
                    _NetCard.muted(
                      caption: home.hasError
                          ? "We couldn't load your balances. Pull down to "
                                'try again.'
                          : '',
                    ),
                  ],
                  HomeData(isEmpty: true) => const [
                    _NetCard.empty(
                      caption:
                          'Nothing recorded yet. Your first entry takes '
                          'about ten seconds.',
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
                    SizedBox(height: SettloSpacing.x3),
                    _JobTile(
                      icon: _LoanIcon(),
                      title: 'Record a loan',
                      body:
                          'Money you lent or borrowed. Both of you see every '
                          'repayment and confirm it.',
                      route: SettloRoutes.newLoan,
                    ),
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
        ],
      ),
    );
  }

  static List<Widget> _balances(HomeData data) => [
    if (data.spaces.isNotEmpty) ...[
      const SizedBox(height: SettloSpacing.x4),
      _SpacesCard(data.spaces),
    ],
    if (data.loans.isNotEmpty) ...[
      const SizedBox(height: SettloSpacing.x3),
      _LoansCard(data.loans),
    ],
    if (!data.isEmpty) ...[
      const SizedBox(height: SettloSpacing.x3),
      const ActivityPreview(),
    ],
  ];

  static Future<void> _refresh(WidgetRef ref) async {
    ref.invalidate(activityFeedProvider);
    await Future.wait([
      ref.refresh(homeProvider.future),
      ref.read(activityFeedProvider.future),
    ]);
  }
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
  const new(this.name);

  final String? name;

  @override
  Widget build(BuildContext context) {
    // The owner's S mark is the header title: in a glass circle on iOS 26,
    // as supplied elsewhere, and no wordmark (#191).
    final lockup = GlassAction(
      label: 'Settlo',
      asset: settloMarkAsset(Theme.of(context).brightness),
      decorative: true,
      onPressed: null,
      fallback: Semantics(
        header: true,
        label: 'Settlo',
        excludeSemantics: true,
        child: const SettloMark(semanticsLabel: null, size: 30),
      ),
    );
    return Row(
      children: [
        Expanded(
          child: Align(
            alignment: Alignment.centerLeft,
            child: FittedBox(fit: BoxFit.scaleDown, child: lockup),
          ),
        ),
        const SizedBox(width: SettloSpacing.x2),
        SettloTabActions(
          name: name,
          onBell: () => context.go(SettloRoutes.activity),
          onProfile: () => context.go(SettloRoutes.profile),
        ),
      ],
    );
  }
}

TextStyle _label(SettloColors c) =>
    SettloTypography.footnote(letterSpacing: 0.3, color: c.textSecondary);

TextStyle _caption(SettloColors c) =>
    SettloTypography.subheadline(color: c.textSecondary);

/// The hero: net position, with owed / owe / month spend when known.
class _NetCard extends StatelessWidget {
  const new(HomeData this.data)
    : label = 'NET POSITION',
      caption = null,
      blank = false,
      whiteZero = false;

  /// ₹0 in muted type: nothing recorded yet, or still loading.
  const new muted({required this.caption})
    : data = null,
      label = 'NET POSITION',
      blank = false,
      whiteZero = false;

  /// ₹0 in white when nothing has been recorded yet.
  const new empty({required this.caption})
    : data = null,
      label = 'NET POSITION',
      blank = false,
      whiteZero = true;

  /// ₹— while claims wait for review.
  const new blank()
    : data = null,
      label = 'NET POSITION · AFTER YOU REVIEW',
      caption = 'Balances appear once you accept or dispute each item above.',
      blank = true,
      whiteZero = false;

  final HomeData? data;
  final String label;
  final String? caption;
  final bool blank;
  final bool whiteZero;

  @override
  Widget build(BuildContext context) {
    const c = SettloColors.dark;
    final data = this.data;
    final String caption;
    final Widget amount;
    if (data == null) {
      caption = this.caption!;
      amount = blank
          ? const MoneyText.blank(size: 46)
          : MoneyText(
              Paise.zero,
              tone: whiteZero ? MoneyTone.neutral : MoneyTone.settled,
              size: 46,
              color: whiteZero ? Colors.white : null,
            );
    } else {
      final net = data.net.value;
      final where = _spacesAndLoans(data.spaces.length, data.loans.length);
      caption = net > 0
          ? 'owed to you across $where'
          : net < 0
          ? 'you owe across $where'
          : 'all settled across $where';
      amount = MoneyText(data.net, size: 46, signed: true, color: Colors.white);
    }
    return Theme(
      data: SettloTheme.dark(),
      child: SCard(
        hero: true,
        padding: EdgeInsets.zero,
        child: Stack(
          children: [
            Positioned.fill(
              child: ExcludeSemantics(
                child: CustomPaint(
                  painter: _NetArcPainter(
                    gold: c.welcomeAction,
                    surface: c.surface,
                  ),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(SettloSpacing.x3),
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
                        Expanded(
                          child: _Stat(
                            'You are owed',
                            data.owed,
                            data.owed.value > 0
                                ? MoneyTone.owedToYou
                                : MoneyTone.settled,
                          ),
                        ),
                        const SizedBox(width: SettloSpacing.x1),
                        Expanded(
                          child: _Stat(
                            'You owe',
                            data.owe,
                            data.owe.value > 0
                                ? MoneyTone.youOwe
                                : MoneyTone.settled,
                          ),
                        ),
                        const SizedBox(width: SettloSpacing.x1),
                        Expanded(
                          child: _Stat(
                            '${_months[data.month.month - 1]} spend',
                            data.monthSpend,
                            MoneyTone.neutral,
                            end: true,
                          ),
                        ),
                      ],
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
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
          style: SettloTypography.footnote(
            color: SettloColors.of(context).textSecondary,
          ),
        ),
        const SizedBox(height: 2),
        FittedBox(
          fit: BoxFit.scaleDown,
          alignment: end ? Alignment.centerRight : Alignment.centerLeft,
          child: MoneyText(amount, tone: tone, size: 17),
        ),
      ],
    ),
  );
}

/// The clipped gold corner treatment from the owner's net-position card.
class _NetArcPainter extends CustomPainter {
  const new({required this.gold, required this.surface});

  final Color gold;
  final Color surface;

  @override
  void paint(Canvas canvas, Size size) {
    final glow = Paint()
      ..shader = RadialGradient(
        center: const Alignment(0.98, -0.94),
        radius: 0.72,
        colors: [
          const Color(0xFFFFF1D2).withValues(alpha: 0.24),
          gold.withValues(alpha: 0.12),
          surface.withValues(alpha: 0),
        ],
        stops: const [0, 0.36, 1],
      ).createShader(Offset.zero & size);
    canvas.drawRect(Offset.zero & size, glow);

    final arc = Path()
      ..moveTo(size.width * 0.58, -2)
      ..quadraticBezierTo(
        size.width * 0.91,
        size.height * 0.19,
        size.width + 6,
        size.height * 0.78,
      );
    canvas
      ..drawPath(
        arc,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 26
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 18)
          ..color = gold.withValues(alpha: 0.1),
      )
      ..drawPath(
        arc,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 4
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 3)
          ..color = const Color(0xFFFFE7B0).withValues(alpha: 0.58),
      )
      ..drawPath(
        arc,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.2
          ..color = gold,
      );
    final lower = Path()
      ..moveTo(size.width * 0.79, size.height + 3)
      ..quadraticBezierTo(
        size.width * 0.91,
        size.height * 0.83,
        size.width + 4,
        size.height * 0.82,
      );
    canvas.drawPath(
      lower,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.2
        ..color = gold.withValues(alpha: 0.85),
    );
  }

  @override
  bool shouldRepaint(_NetArcPainter oldDelegate) =>
      oldDelegate.gold != gold || oldDelegate.surface != surface;
}

class _Actions extends StatelessWidget {
  @override
  Widget build(BuildContext context) => SResponsiveRow(
    threshold: 1.3,
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
      padding: const EdgeInsets.all(SettloSpacing.screenMargin),
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
          child: SPressable(
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
      child: SPressable(
        onTap: onTap,
        child: Container(
          constraints: const BoxConstraints(
            minHeight: SettloSpacing.minTouchTarget,
          ),
          padding: padding,
          child: SResponsiveRow(
            children: [
              leading,
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      maxLines: MediaQuery.textScalerOf(context).scale(1) >= 1.5
                          ? null
                          : 1,
                      overflow: TextOverflow.ellipsis,
                      style: SettloTypography.headline(color: c.textPrimary),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      detail,
                      semanticsLabel: detailSpoken,
                      style: SettloTypography.footnote(color: c.textSecondary)
                          .copyWith(height: 1.3),
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
    final color = tile ? c.textPrimary : c.homeGold;
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
    data: IconThemeData(color: SettloColors.of(context).homeGold, size: 22),
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
            onTap: () => context.go(SettloRoutes.loan(l.id)),
          ),
          if ((l.pendingRepaymentId, l.pendingRepaymentAmount) case (
            final repaymentId?,
            final amount?,
          )) ...[
            const SizedBox(height: 10),
            _Row(
              padding: const EdgeInsets.symmetric(vertical: 8),
              leading: const SizedBox(width: 44),
              title: '${l.counterparty} says they paid',
              detail: '${formatInr(amount)} · Review repayment',
              detailSpoken: '${spokenInr(amount)} · Review repayment',
              onTap: () =>
                  context.push(SettloRoutes.confirmRepayment(repaymentId)),
            ),
          ],
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
    return _HomePressable(
      label: title,
      onTap: () => context.push(route),
      child: SCard(
        padding: const EdgeInsets.all(SettloSpacing.screenMargin),
        child: LayoutBuilder(
          builder: (context, constraints) {
            final largeText = MediaQuery.textScalerOf(context).scale(1) > 1.4;
            final copy = Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: 44,
                  height: 44,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: c.homeGold.withValues(alpha: 0.14),
                    borderRadius: BorderRadius.circular(SettloRadius.button),
                  ),
                  child: icon,
                ),
                const SizedBox(height: SettloSpacing.x2),
                Text(
                  title,
                  style: SettloTypography.title3(
                    letterSpacing: -0.3,
                    color: c.textPrimary,
                  ),
                ),
                const SizedBox(height: 4),
                Text(body, style: _caption(c).copyWith(height: 1.45)),
              ],
            );
            final arrow = Container(
              width: SettloHomeMetrics.arrowButton,
              height: SettloHomeMetrics.arrowButton,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: c.homeGold.withValues(alpha: 0.22),
                shape: BoxShape.circle,
              ),
              child: HomeIcon(
                HomeGlyph.arrow,
                color: c.homeGold,
                size: 22,
                stroke: 2,
              ),
            );
            if (largeText) {
              return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  copy,
                  const SizedBox(height: SettloSpacing.x3),
                  Align(alignment: Alignment.centerRight, child: arrow),
                ],
              );
            }
            return Row(
              children: [
                Expanded(child: copy),
                const SizedBox(width: 12),
                arrow,
              ],
            );
          },
        ),
      ),
    );
  }
}

class _HomePressable extends StatelessWidget {
  const new({required this.label, required this.onTap, required this.child});

  final String label;
  final VoidCallback onTap;
  final Widget child;

  @override
  Widget build(BuildContext context) =>
      SPressable(label: label, onTap: onTap, child: child);
}

/// A text-only action with a target of at least 44x44pt.
class _TextAction extends StatelessWidget {
  const new(this.label, {required this.color, required this.onTap});

  final String label;
  final Color color;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => TextButton(
    onPressed: onTap,
    style: TextButton.styleFrom(
      foregroundColor: color,
      alignment: Alignment.centerLeft,
      minimumSize: const Size.square(SettloSpacing.minTouchTarget),
      padding: EdgeInsets.zero,
      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
      textStyle: SettloTypography.subheadline(weight: FontWeight.w500),
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
      padding: const EdgeInsets.all(SettloSpacing.x3),
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
                      style: SettloTypography.callout(
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
          const SizedBox(height: SettloSpacing.x3),
          for (final (i, claim) in claims.indexed)
            _ClaimRow(claim, divider: i < claims.length - 1),
        ],
      ),
    );
  }
}

class _ClaimRow extends ConsumerStatefulWidget {
  const new(this.claim, {required this.divider});

  final Claim claim;
  final bool divider;

  @override
  ConsumerState<_ClaimRow> createState() => _ClaimRowState();
}

class _ClaimRowState extends ConsumerState<_ClaimRow> {
  // One key per button, reused when a failed answer is tried again.
  final String _acceptKey = newIdempotencyKey();
  final String _rejectKey = newIdempotencyKey();
  bool _busy = false;

  Claim get claim => widget.claim;

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

  Future<void> _settle(Future<void> Function(HomeController) call) async {
    // Not state: a second tap in the same frame must see it.
    if (_busy) return;
    _busy = true;
    final root = Navigator.of(context, rootNavigator: true).context;
    try {
      await call(ref.read(homeProvider.notifier));
    } on SessionEnded {
      // Signed out mid-tap: the user has left, so there is nothing to say.
    } on Exception {
      if (root.mounted) {
        showSettloNotice(
          root,
          "We couldn't save that. Check your connection and try again.",
        );
      }
    } finally {
      _busy = false;
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = SettloColors.of(context);
    return Container(
      padding: const EdgeInsets.only(top: 14, bottom: SettloSpacing.half),
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
                  style: SettloTypography.headline(color: c.textPrimary),
                ),
                const SizedBox(height: 3),
                Text(
                  _says(formatInr),
                  semanticsLabel: _says(spokenInr),
                  style: SettloTypography.footnote(color: c.textSecondary)
                      .copyWith(height: 1.3),
                ),
                Wrap(
                  spacing: SettloSpacing.x2,
                  runSpacing: SettloSpacing.half,
                  children: [
                    _TextAction(
                      'Accept',
                      color: c.action,
                      onTap: () => _settle(
                        (h) => h.accept(claim, idempotencyKey: _acceptKey),
                      ),
                    ),
                    _TextAction(
                      "This isn't me",
                      color: c.textSecondary,
                      onTap: () => _settle(
                        (h) => h.reject(claim, idempotencyKey: _rejectKey),
                      ),
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
      padding: const EdgeInsets.all(SettloSpacing.screenMargin),
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
