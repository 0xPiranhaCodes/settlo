import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:settlo_core/settlo_core.dart';
import 'package:settlo_spaces/src/space_detail.dart';
import 'package:settlo_spaces/src/spaces_controller.dart';

/// A pending settle-up opened by path, such as from Activity's 'Needs
/// you': once its space and ledger load, [ConfirmSettlementSheet] answers
/// it exactly as from the space.
class ConfirmSettlementScreen extends ConsumerStatefulWidget {
  /// The settle-up [expenseId] in [spaceId].
  const new({required this.spaceId, required this.expenseId, super.key});

  /// The settle-up's space.
  final String spaceId;

  /// The settle-up (`expenses.id`).
  final String expenseId;

  @override
  ConsumerState<ConfirmSettlementScreen> createState() => _State();
}

class _State extends ConsumerState<ConfirmSettlementScreen> {
  /// Kept once shown: answering reloads the ledger, where it is no longer
  /// pending, and the sheet must stay until it closes itself.
  (SpaceSummary, SpaceExpense, String)? _shown;

  @override
  Widget build(BuildContext context) {
    final c = SettloColors.of(context);
    final spaces = ref.watch(spacesProvider);
    final ledger = ref.watch(spaceLedgerProvider(widget.spaceId));
    final space = spaces.value
        ?.where((s) => s.id == widget.spaceId)
        .firstOrNull;
    final expense = ledger.value?.expenses
        .where(
          (e) =>
              e.id == widget.expenseId &&
              e.settlementStatus == SettlementStatus.pending,
        )
        .firstOrNull;
    if (_shown == null && space != null && expense != null) {
      final payee = space.members
          .where((m) => m.id == expense.splits.single.memberId)
          .firstOrNull;
      if (payee?.isYou ?? false) {
        final payer = [
          ...space.members,
          ...space.departed,
        ].where((m) => m.id == expense.payers.single.memberId).firstOrNull;
        _shown = (space, expense, payer?.name ?? 'They');
      }
    }
    final loading = spaces.isLoading || ledger.isLoading;
    return Padding(
      padding: EdgeInsets.only(
        top: settloSheetTop(context),
        bottom: MediaQuery.viewInsetsOf(context).bottom,
      ),
      child: Material(
        type: MaterialType.transparency,
        child: switch (_shown) {
          (final s, final e, final payer) => ConfirmSettlementSheet(
            space: s,
            expense: e,
            payer: payer,
          ),
          null => SAmountSheet(
            title: 'Confirm settle-up',
            onClose: () => context.pop(),
            amountLabel: 'Settle-up',
            amount: const Text('—'),
            body: Text(
              loading
                  ? ''
                  : 'This settle-up was already answered, or is no longer '
                        'yours to confirm.',
              textAlign: TextAlign.center,
              style: SettloTypography.subheadline(color: c.textSecondary),
            ),
          ),
        },
      ),
    );
  }
}
