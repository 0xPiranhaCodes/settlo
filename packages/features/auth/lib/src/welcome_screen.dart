import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:settlo_auth/src/widgets.dart';
import 'package:settlo_core/settlo_core.dart';

/// Welcome: what the ledger looks like, with the rows marked as examples,
/// and one action, continue with phone (canvas note n00).
class WelcomeScreen extends StatelessWidget {
  /// The Welcome screen.
  const new({super.key});

  @override
  Widget build(BuildContext context) {
    final c = SettloColors.of(context);
    return AuthPage(
      topInset: 26,
      bottomInset: SettloSpacing.x3,
      top: const Padding(
        padding: EdgeInsets.symmetric(horizontal: SettloSpacing.x3),
        child: _Wordmark(),
      ),
      content: [
        const Spacer(),
        const SizedBox(height: SettloSpacing.x4),
        Semantics(
          header: true,
          child: Text(
            'Money between friends,\nfinally settled.',
            style: SettloTypography.figtree(
              38,
              weight: FontWeight.w500,
              letterSpacing: -1.2,
              color: c.textPrimary,
            ).copyWith(height: 1.1),
          ),
        ),
        const SizedBox(height: SettloSpacing.x2),
        Text(
          'Flatmates, trips, and the ₹10 lakh you lent your friend — one '
          'quiet ledger you both can see.',
          style: SettloTypography.figtree(
            16,
            color: c.textSecondary,
          ).copyWith(height: 1.5),
        ),
        const SizedBox(height: SettloSpacing.x4),
        const _ExamplesLabel(),
        const SizedBox(height: 10),
        const _ExampleRow(
          name: 'Rahul',
          title: 'Rahul owes you',
          detail: 'Flat 402 · groceries, wifi',
          amount: Paise.rupees(750),
        ),
        const SizedBox(height: 14),
        const _ExampleRow(
          name: 'Arjun',
          title: 'Arjun repaid',
          detail: '13 of 40 · on schedule',
          amount: Paise.rupees(25000),
        ),
        const SizedBox(height: 36),
      ],
      bottom: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          AuthButton(
            label: 'Continue with phone number',
            arrow: true,
            onPressed: () => context.go(SettloRoutes.phone),
          ),
          const SizedBox(height: SettloSpacing.x2),
          Text(
            'No email. No password. Your number is your account.',
            textAlign: TextAlign.center,
            style: SettloTypography.figtree(12, color: c.textMuted),
          ),
        ],
      ),
    );
  }
}

class _Wordmark extends StatelessWidget {
  const new();

  @override
  Widget build(BuildContext context) {
    final c = SettloColors.of(context);
    return Semantics(
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
            child: AuthIcon(
              AuthGlyph.mark,
              color: c.onAction,
              size: 13,
              stroke: 3.2,
            ),
          ),
          const SizedBox(width: SettloSpacing.x1),
          Text(
            'settlo',
            style: SettloTypography.figtree(
              24,
              weight: FontWeight.w500,
              letterSpacing: -0.6,
              color: c.textPrimary,
            ),
          ),
        ],
      ),
    );
  }
}

class _ExamplesLabel extends StatelessWidget {
  const new();

  @override
  Widget build(BuildContext context) {
    final c = SettloColors.of(context);
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Flexible(
          child: Text(
            'WHAT IT LOOKS LIKE',
            style: SettloTypography.figtree(
              12,
              letterSpacing: 0.3,
              color: c.textSecondary,
            ),
          ),
        ),
        const SizedBox(width: SettloSpacing.x1),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
          decoration: BoxDecoration(
            border: Border.all(color: c.textSecondary),
            borderRadius: BorderRadius.circular(6),
          ),
          child: Text(
            'example',
            style: SettloTypography.figtree(
              11,
              color: c.textSecondary,
            ).copyWith(height: 1.3),
          ),
        ),
      ],
    );
  }
}

/// A made-up ledger row. The amounts are neutral, as on the canvas: they are
/// nobody's money.
class _ExampleRow extends StatelessWidget {
  const new({
    required this.name,
    required this.title,
    required this.detail,
    required this.amount,
  });

  final String name;
  final String title;
  final String detail;
  final Paise amount;

  @override
  Widget build(BuildContext context) {
    final c = SettloColors.of(context);
    return SCard(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      child: Row(
        children: [
          SAvatar(name, size: 36),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: SettloTypography.figtree(14, color: c.textPrimary),
                ),
                Text(
                  detail,
                  style: SettloTypography.figtree(12, color: c.textSecondary),
                ),
              ],
            ),
          ),
          MoneyText(amount, size: 16),
        ],
      ),
    );
  }
}
