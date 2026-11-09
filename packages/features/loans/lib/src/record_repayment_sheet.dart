import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:settlo_core/settlo_core.dart';

/// Opens [RecordRepaymentSheet] for [loan].
Future<void> showRecordRepaymentSheet(BuildContext context, Loan loan) =>
    showSAmountSheet<void>(
      context: context,
      builder: (context) => RecordRepaymentSheet(
        loan: loan,
        onClose: () => Navigator.of(context).pop(),
      ),
    );

/// Record repayment: the amount first, in the serif, then how it was
/// paid. It is saved pending; the other party confirms it before it
/// counts. One idempotency key is made when the sheet opens and sent with
/// every attempt, so saving again after a dropped connection never
/// records it twice.
class RecordRepaymentSheet extends ConsumerStatefulWidget {
  /// The sheet for [loan].
  const new({required this.loan, required this.onClose, super.key});

  /// The loan repaid.
  final Loan loan;

  /// Closes the sheet; also called once the repayment is recorded.
  final VoidCallback onClose;

  @override
  ConsumerState<RecordRepaymentSheet> createState() => _RecordState();
}

class _RecordState extends ConsumerState<RecordRepaymentSheet> {
  final String _key = newIdempotencyKey();
  late final _amount = TextEditingController(
    text: switch (widget.loan.installment) {
      final i? when i.value <= widget.loan.outstanding.value => _typed(i),
      _ => '',
    },
  );
  final _reference = TextEditingController();
  DateTime? _paidOn;
  RepaymentMethod _method = RepaymentMethod.upi;
  bool _busy = false;
  String? _error;

  static String _typed(Paise p) => formatInr(p).substring(1);

  @override
  void dispose() {
    _amount.dispose();
    _reference.dispose();
    super.dispose();
  }

  Future<void> _save(Paise amount) async {
    // The button disables only on the next frame; a second tap in this
    // one must not send again.
    if (_busy) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    final ledger = ref.read(ledgerRevisionProvider.notifier);
    try {
      await ref.read(loansRepositoryProvider).recordRepayment((
        loanId: widget.loan.id,
        amount: amount,
        method: _method,
        paidOn: _paidOn,
        reference: switch (_reference.text.trim()) {
          '' => null,
          final value => value,
        },
      ), idempotencyKey: _key);
      ledger.bump();
      widget.onClose();
      // Done: stay busy, so a tap still queued on this frame is dropped.
      return;
    } on IdempotencyConflict {
      ledger.bump();
      _error = 'This repayment was already recorded. Close this to see it.';
    } on LoanRejected catch (e) {
      _error = e.message;
    } on Exception {
      _error =
          "We couldn't record it. Check your connection and try again. "
          "It won't be recorded twice.";
    }
    if (mounted) setState(() => _busy = false);
  }

  Future<void> _pickDate() async {
    final today = DateUtils.dateOnly(DateTime.now());
    final picked = await showDatePicker(
      context: context,
      initialDate: _paidOn ?? today,
      firstDate: DateUtils.dateOnly(widget.loan.startOn),
      lastDate: today,
    );
    if (picked == null) return;
    setState(() => _paidOn = picked == today ? null : picked);
  }

  @override
  Widget build(BuildContext context) {
    final c = SettloColors.of(context);
    final loan = widget.loan;
    final who = loan.counterparty;
    final amount = parseInr(_amount.text) ?? Paise.zero;
    final over = amount.value > loan.outstanding.value;
    final note = SettloTypography.figtree(13, color: c.textSecondary);
    return SAmountSheet(
      title: 'Record repayment · $who',
      onClose: widget.onClose,
      amountLabel: loan.youLent ? '$who paid you' : 'You paid $who',
      amount: Builder(
        builder: (context) {
          final style = DefaultTextStyle.of(context).style;
          return IntrinsicWidth(
            child: Semantics(
              label: 'Amount in rupees',
              child: TextField(
                controller: _amount,
                autofocus: true,
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                ),
                inputFormatters: [
                  TextInputFormatter.withFunction(
                    (old, next) => _rupees.hasMatch(next.text) ? next : old,
                  ),
                ],
                onChanged: (_) => setState(() => _error = null),
                style: style,
                cursorColor: c.textPrimary,
                decoration:
                    InputDecoration.collapsed(
                      hintText: '0',
                      hintStyle: style.copyWith(color: c.textMuted),
                    ).copyWith(
                      enabledBorder: InputBorder.none,
                      focusedBorder: InputBorder.none,
                    ),
              ),
            ),
          );
        },
      ),
      body: ListView(
        padding: EdgeInsets.zero,
        children: [
          Semantics(
            label: '${spokenInr(loan.outstanding)} left',
            excludeSemantics: true,
            child: Text(
              '${formatInr(loan.outstanding)} left',
              textAlign: TextAlign.center,
              style: note,
            ),
          ),
          const SizedBox(height: 22),
          Text(
            'PAID BY',
            style: SettloTypography.figtree(
              12,
              letterSpacing: 0.3,
              color: c.textSecondary,
            ),
          ),
          const SizedBox(height: 6),
          Wrap(
            spacing: SettloSpacing.x1,
            children: [
              for (final m in RepaymentMethod.values)
                SChip(
                  label: m.label,
                  selected: _method == m,
                  onSelected: (_) => setState(() => _method = m),
                ),
            ],
          ),
          const SizedBox(height: 18),
          Text('PAID ON', style: _sheetLabel(c)),
          const SizedBox(height: 6),
          Align(
            alignment: Alignment.centerLeft,
            child: SChip(
              label: switch (_paidOn) {
                null => 'Today',
                final d => '${d.day} ${_months[d.month - 1]} ${d.year}',
              },
              selected: _paidOn != null,
              onSelected: (_) => _pickDate(),
            ),
          ),
          const SizedBox(height: 18),
          Text('REFERENCE · OPTIONAL', style: _sheetLabel(c)),
          const SizedBox(height: 6),
          TextField(
            controller: _reference,
            maxLength: 64,
            textCapitalization: TextCapitalization.characters,
            onChanged: (_) => setState(() => _error = null),
            style: SettloTypography.figtree(15, color: c.textPrimary),
            decoration: const InputDecoration(
              hintText: 'UPI or bank reference',
              counterText: '',
            ),
          ),
          if (over || _error != null) ...[
            const SizedBox(height: 14),
            Text(
              _error ?? "That's more than is left on the loan.",
              textAlign: TextAlign.center,
              style: SettloTypography.figtree(13, color: c.textPrimary),
            ),
          ],
        ],
      ),
      action: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            "Settlo doesn't move money. $who confirms it before it counts.",
            textAlign: TextAlign.center,
            style: note,
          ),
          const SizedBox(height: 14),
          SPrimaryButton(
            label: _busy ? 'Recording…' : 'Record repayment',
            onPressed: _busy || amount.value == 0 || over
                ? null
                : () => _save(amount),
          ),
        ],
      ),
    );
  }
}

/// Rupees as typed: up to nine digits, commas allowed, two decimals.
final _rupees = RegExp(r'^[\d,]{0,11}(\.\d{0,2})?$');

const _months = [
  'Jan',
  'Feb',
  'Mar',
  'Apr',
  'May',
  'Jun',
  'Jul',
  'Aug',
  'Sep',
  'Oct',
  'Nov',
  'Dec',
];

TextStyle _sheetLabel(SettloColors c) =>
    SettloTypography.figtree(12, letterSpacing: 0.3, color: c.textSecondary);
