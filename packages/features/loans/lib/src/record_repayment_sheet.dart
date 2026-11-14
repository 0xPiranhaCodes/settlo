import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:settlo_core/settlo_core.dart';
import 'package:settlo_loans/src/loans_provider.dart';

/// Opens [RecordRepaymentSheet] for [loan].
Future<void> showRecordRepaymentSheet(BuildContext context, Loan loan) =>
    showSAmountSheet<void>(
      context: context,
      builder: (context) => RecordRepaymentSheet(
        loan: loan,
        onClose: () => finishSettloSheet(context),
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
  late final DateTime _today = ref.read(indiaTodayProvider);
  late final String _suggested = switch (widget.loan.installment) {
    final i? when i.value <= widget.loan.outstanding.value => _typed(i),
    _ => '',
  };
  late final _amount = TextEditingController(text: _suggested);
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
        reference: switch (_normalizeReference(_reference.text)) {
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
    } on SessionEnded {
      // Signed out mid-tap: the user has left, so there is nothing to say.
    } on Exception {
      _error =
          "We couldn't record it. Check your connection and try again. "
          "It won't be recorded twice.";
    }
    if (mounted) setState(() => _busy = false);
  }

  Future<void> _pickDate() async {
    final picked = await showSettloDatePicker(
      context: context,
      initialDate: _paidOn ?? _today,
      firstDate: DateUtils.dateOnly(widget.loan.startOn),
      lastDate: _today,
    );
    if (picked == null) return;
    setState(() => _paidOn = picked == _today ? null : picked);
  }

  @override
  Widget build(BuildContext context) {
    final c = SettloColors.of(context);
    final loan = widget.loan;
    final who = loan.counterparty;
    final amount = parseInr(_amount.text) ?? Paise.zero;
    final over = amount.value > loan.outstanding.value;
    final note = SettloTypography.subheadline(color: c.textSecondary);
    return SAmountSheet(
      title: 'Record repayment · $who',
      onClose: widget.onClose,
      dirty:
          _amount.text != _suggested ||
          _reference.text.isNotEmpty ||
          _paidOn != null ||
          _method != RepaymentMethod.upi,
      saving: _busy,
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
      body: SFormBody(
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
          const SizedBox(height: SettloSpacing.x3),
          Text(
            'PAID BY',
            style: SettloTypography.footnote(
              letterSpacing: 0.3,
              color: c.textSecondary,
            ),
          ),
          const SizedBox(height: SettloSpacing.x1),
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
          const SizedBox(height: SettloSpacing.x3),
          Text('PAID ON', style: _sheetLabel(c)),
          const SizedBox(height: SettloSpacing.x1),
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
          const SizedBox(height: SettloSpacing.x3),
          Text('REFERENCE · OPTIONAL', style: _sheetLabel(c)),
          const SizedBox(height: SettloSpacing.x1),
          TextField(
            controller: _reference,
            maxLength: 64,
            maxLengthEnforcement: MaxLengthEnforcement.none,
            inputFormatters: [_RepaymentReferenceFormatter()],
            textCapitalization: TextCapitalization.characters,
            onChanged: (_) => setState(() => _error = null),
            style: SettloTypography.headline(color: c.textPrimary),
            decoration: const InputDecoration(
              hintText: 'UPI or bank reference',
              counterText: '',
            ),
          ),
          if (over || _error != null) ...[
            const SizedBox(height: SettloSpacing.x2),
            Text(
              _error ?? "That's more than is left on the loan.",
              textAlign: TextAlign.center,
              style: SettloTypography.subheadline(color: c.textPrimary),
            ),
          ],
        ],
      ),
      action: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            "SabkiJeb doesn't move money. $who confirms it before it counts.",
            textAlign: TextAlign.center,
            style: note,
          ),
          const SizedBox(height: SettloSpacing.x2),
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

/// Mirrors the server's Unicode whitespace trim before its 64-code-point
/// bound. Controls and format characters are filtered client-side.
String _normalizeReference(String value) =>
    _trimUnicodeWhitespace(_withoutControlOrFormat(value));

String _withoutControlOrFormat(String value) => String.fromCharCodes(
  value.runes.where((rune) => !_isControlOrFormat(rune)),
);

String _trimUnicodeWhitespace(String value) {
  final runes = value.runes.toList(growable: false);
  var start = 0;
  var end = runes.length;
  while (start < end && _isUnicodeWhitespace(runes[start])) {
    start++;
  }
  while (end > start && _isUnicodeWhitespace(runes[end - 1])) {
    end--;
  }
  return String.fromCharCodes(runes.sublist(start, end));
}

bool _isUnicodeWhitespace(int rune) =>
    (rune >= 0x0009 && rune <= 0x000D) ||
    rune == 0x0020 ||
    rune == 0x0085 ||
    rune == 0x00A0 ||
    rune == 0x1680 ||
    (rune >= 0x2000 && rune <= 0x200A) ||
    (rune >= 0x2028 && rune <= 0x2029) ||
    rune == 0x202F ||
    rune == 0x205F ||
    rune == 0x3000;

bool _isControlOrFormat(int rune) =>
    rune <= 0x001F ||
    (rune >= 0x007F && rune <= 0x009F) ||
    rune == 0x00AD ||
    (rune >= 0x0600 && rune <= 0x0605) ||
    rune == 0x061C ||
    rune == 0x06DD ||
    rune == 0x070F ||
    (rune >= 0x0890 && rune <= 0x0891) ||
    rune == 0x08E2 ||
    (rune >= 0x17B4 && rune <= 0x17B5) ||
    rune == 0x180E ||
    (rune >= 0x200B && rune <= 0x200F) ||
    (rune >= 0x202A && rune <= 0x202E) ||
    (rune >= 0x2060 && rune <= 0x2064) ||
    (rune >= 0x2066 && rune <= 0x206F) ||
    rune == 0xFEFF ||
    (rune >= 0xFFF9 && rune <= 0xFFFB) ||
    rune == 0x110BD ||
    rune == 0x110CD ||
    (rune >= 0x13430 && rune <= 0x1343F) ||
    (rune >= 0x1BCA0 && rune <= 0x1BCA3) ||
    (rune >= 0x1D173 && rune <= 0x1D17A) ||
    rune == 0xE0001 ||
    (rune >= 0xE0020 && rune <= 0xE007F);

final class _RepaymentReferenceFormatter extends TextInputFormatter {
  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    final filtered = _withoutControlOrFormat(newValue.text);
    final normalized = _trimUnicodeWhitespace(filtered);
    final normalizedRunes = normalized.runes.toList(growable: false);
    final text = normalizedRunes.length <= 64
        ? filtered
        : String.fromCharCodes(normalizedRunes.take(64));
    int remap(int offset) {
      if (offset < 0) return offset;
      final end = offset.clamp(0, newValue.text.length);
      return _withoutControlOrFormat(newValue.text.substring(0, end)).length
          .clamp(0, text.length);
    }

    return TextEditingValue(
      text: text,
      selection: TextSelection(
        baseOffset: remap(newValue.selection.baseOffset),
        extentOffset: remap(newValue.selection.extentOffset),
        affinity: newValue.selection.affinity,
        isDirectional: newValue.selection.isDirectional,
      ),
    );
  }
}

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
    SettloTypography.footnote(letterSpacing: 0.3, color: c.textSecondary);
