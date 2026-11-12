import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:settlo_core/settlo_core.dart';
import 'package:settlo_loans/src/glyphs.dart';
import 'package:settlo_loans/src/loans_provider.dart';
import 'package:settlo_platform/settlo_platform.dart';

/// New loan (NewLoan artboard, note n21), risen to 54px below the top of
/// the screen over whatever opened it: direction first, then the
/// principal in the serif with its amount in words underneath, who it is
/// with, and the monthly schedule. Interest is off, with the way to add it
/// later shown but not yet open. The footer says what happens before the
/// user commits.
///
/// One idempotency key is made when the sheet opens and sent with every
/// attempt, so creating again after a dropped connection never makes a
/// second loan. Once created it opens WhatsApp to tell the other person,
/// then shows the loan.
class NewLoanSheet extends ConsumerStatefulWidget {
  /// The sheet.
  const new({super.key});

  @override
  ConsumerState<NewLoanSheet> createState() => _NewLoanState();
}

class _NewLoanState extends ConsumerState<NewLoanSheet> {
  final String _key = newIdempotencyKey();
  final String _inviteKey = newIdempotencyKey();
  final _principal = TextEditingController();
  final _installment = TextEditingController();
  final _phone = TextEditingController();
  final _person = TextEditingController();
  bool _youLent = true;
  ({String phone, String name})? _who;
  late final DateTime _today = ref.read(indiaTodayProvider);
  late DateTime _start = _today;
  late int _dueDay = math.min(_today.day, 28);
  String? _phoneError;
  String? _error;
  bool _busy = false;

  @override
  void dispose() {
    _principal.dispose();
    _installment.dispose();
    _phone.dispose();
    _person.dispose();
    super.dispose();
  }

  void _close() =>
      context.canPop() ? context.pop() : context.go(SettloRoutes.loans);

  /// Picks the other person the way a space adds a member: a number,
  /// read as E.164, and an optional name.
  void _add() {
    final phone = toE164(_phone.text);
    // GoTrue stores the verified number without its `+`.
    final mine = ref.read(sessionProvider)?.user.phone;
    setState(() {
      if (phone == null) {
        _phoneError = 'Enter a mobile number, like 98765 43210';
      } else if (mine != null &&
          phone == toE164('+${mine.replaceFirst('+', '')}')) {
        _phoneError = "That's your number. A loan is with someone else.";
      } else {
        final name = _person.text.trim();
        _who = (phone: phone, name: name.isEmpty ? groupPhone(phone) : name);
        _phoneError = null;
      }
    });
  }

  Future<void> _pickStart() async {
    final picked = await showSettloDatePicker(
      context: context,
      initialDate: _start,
      firstDate: DateTime(2000),
      lastDate: DateTime(_today.year + 1, _today.month, _today.day),
      helpText: 'Loan starts',
    );
    if (picked != null) setState(() => _start = picked);
  }

  Future<void> _pickDueDay() async {
    final picked = await showSettloPicker<int>(
      context: context,
      values: [for (var d = 1; d <= 28; d++) d],
      selected: _dueDay,
      label: ordinal,
    );
    if (picked != null) setState(() => _dueDay = picked);
  }

  Future<void> _create(NewLoan loan) async {
    // The button disables only on the next frame; a second tap in this
    // one must not send again.
    if (_busy) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    final ledger = ref.read(ledgerRevisionProvider.notifier);
    final open = ref.read(openUrlProvider);
    final root = Navigator.of(context, rootNavigator: true).context;
    final router = GoRouter.of(context);
    try {
      final id = await ref
          .read(loansRepositoryProvider)
          .createLoan(loan, idempotencyKey: _key);
      if (loan.installment != null && mounted) {
        await showReminderPermission(
          context,
          ref,
          ReminderPermissionTrigger.instalmentLoan,
        );
      }
      if (!mounted) return;
      final token = await ref
          .read(invitesRepositoryProvider)
          .issueLoan(id, idempotencyKey: _inviteKey);
      ledger.bump();
      final opened = await open(
        Uri.https('wa.me', '/${loan.counterpartyPhone.substring(1)}', {
          'text': loanInviteText(_yourName, inviteLink(token)),
        }),
      ).catchError((_) => false);
      router.go(SettloRoutes.loan(id));
      if (!opened) {
        // On the loan's page, which has the Scaffold to show it.
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (root.mounted) showSettloNotice(root, "Couldn't open WhatsApp");
        });
      }
      // Done: stay busy, so a tap still queued on this frame is dropped.
      return;
    } on IdempotencyConflict {
      ledger.bump();
      _error =
          'This loan was already created with the details you first '
          'entered. Close this to see it.';
    } on LoanRejected catch (e) {
      _error = e.message;
    } on SessionEnded {
      // Signed out mid-tap: the user has left, so there is nothing to say.
    } on Exception {
      _error =
          "We couldn't create the loan. Check your connection and try "
          "again. It won't be created twice.";
    }
    if (mounted) setState(() => _busy = false);
  }

  /// Your profile name, from the loans load (kept alive while open).
  String? get _yourName => ref.read(loansProvider).value?.yourName;

  @override
  Widget build(BuildContext context) {
    ref.watch(loansProvider);
    final c = SettloColors.of(context);
    final media = MediaQuery.of(context);
    final label = SettloTypography.footnote(
      letterSpacing: 0.3,
      color: c.textSecondary,
    );
    final largeText = MediaQuery.textScalerOf(context).scale(14) > 21;
    final ios = Theme.of(context).platform == TargetPlatform.iOS;
    Widget field({required Widget child, double? width}) => largeText
        ? child
        : width == null
        ? Expanded(child: child)
        : SizedBox(width: width, child: child);
    const gap = SizedBox(height: 16);
    final principal = parseInr(_principal.text) ?? Paise.zero;
    final installment = _installment.text.isEmpty
        ? null
        : parseInr(_installment.text) ?? Paise.zero;
    final badInstallment =
        installment != null &&
        (installment.value == 0 || installment.value > principal.value);
    final who = _who;
    final first = who?.name.split(' ').first;
    final schedule = switch (installment) {
      _ when principal.value == 0 || badInstallment => '',
      null => ' No monthly schedule; repay any time.',
      final i =>
        ' Ends ${monthYear(loanEndMonth(_start, principal, i))} at this '
            'pace.',
    };
    final loan = who == null || principal.value == 0 || badInstallment
        ? null
        : (
            youLent: _youLent,
            counterpartyPhone: who.phone,
            principal: principal,
            installment: installment,
            dueDay: installment == null ? null : _dueDay,
            startOn: _start,
          );
    return Padding(
      padding: EdgeInsets.only(
        top: settloSheetTop(context),
        bottom: media.viewInsets.bottom,
      ),
      child: Material(
        type: MaterialType.transparency,
        child: SAmountSheet(
          title: 'New loan',
          // Every editable field, against its value when the sheet opened.
          dirty:
              !_youLent ||
              _who != null ||
              _start != _today ||
              _dueDay != math.min(_today.day, 28) ||
              [
                _principal,
                _installment,
                _phone,
                _person,
              ].any((c) => c.text.isNotEmpty),
          saving: _busy,
          onClose: _close,
          header: _Direction(
            youLent: _youLent,
            onChanged: (v) => setState(() => _youLent = v),
          ),
          amountLabel: 'Principal',
          amount: Builder(
            builder: (context) {
              final style = DefaultTextStyle.of(context).style;
              // Empty, the hint alone would be under 44pt wide.
              return ConstrainedBox(
                constraints: const BoxConstraints(
                  minWidth: SettloSpacing.minTouchTarget,
                ),
                child: IntrinsicWidth(
                  child: Semantics(
                    label: 'Principal in rupees',
                    child: TextField(
                      controller: _principal,
                      textAlign: TextAlign.center,
                      keyboardType: const TextInputType.numberWithOptions(
                        decimal: true,
                      ),
                      inputFormatters: [
                        TextInputFormatter.withFunction(
                          (old, next) =>
                              _rupees.hasMatch(next.text) ? next : old,
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
                            filled: false,
                          ),
                    ),
                  ),
                ),
              );
            },
          ),
          body: SFormBody(
            children: [
              // So ₹10,00,000 is never misread as one lakh (n21).
              Text(
                principal.value == 0 ? '' : amountInWords(principal),
                textAlign: TextAlign.center,
                style: SettloTypography.subheadline(color: c.textSecondary),
              ),
              const SizedBox(height: SettloSpacing.x3),
              Text(_youLent ? 'TO' : 'FROM', style: label),
              const SizedBox(height: SettloSpacing.x1),
              if (who != null)
                _Person(who: who, onChange: () => setState(() => _who = null))
              else ...[
                TextField(
                  controller: _phone,
                  keyboardType: TextInputType.phone,
                  autofillHints: const [AutofillHints.telephoneNumber],
                  onChanged: (_) => setState(() {}),
                  onSubmitted: (_) => _add(),
                  decoration: InputDecoration(
                    labelText: 'Phone number',
                    hintText: '98765 43210',
                    errorText: _phoneError,
                  ),
                ),
                const SizedBox(height: SettloSpacing.x2),
                TextField(
                  controller: _person,
                  textCapitalization: TextCapitalization.words,
                  onChanged: (_) => setState(() {}),
                  onSubmitted: (_) => _add(),
                  decoration: const InputDecoration(labelText: 'Their name'),
                ),
                const SizedBox(height: SettloSpacing.x2),
                SSecondaryButton(
                  label: 'Add person',
                  icon: LoanGlyph(
                    LoanGlyph.plus,
                    color: c.textPrimary,
                    size: 18,
                  ),
                  onPressed: _add,
                ),
              ],
              gap,
              Flex(
                direction: largeText ? Axis.vertical : Axis.horizontal,
                crossAxisAlignment: largeText
                    ? CrossAxisAlignment.stretch
                    : CrossAxisAlignment.start,
                children: [
                  field(
                    child: _Labelled(
                      label: 'REPAY MONTHLY',
                      child: TextField(
                        controller: _installment,
                        keyboardType: const TextInputType.numberWithOptions(
                          decimal: true,
                        ),
                        inputFormatters: [
                          TextInputFormatter.withFunction(
                            (old, next) =>
                                _rupees.hasMatch(next.text) ? next : old,
                          ),
                        ],
                        onChanged: (_) => setState(() => _error = null),
                        decoration: const InputDecoration(
                          prefixText: '₹',
                          hintText: 'Flexible',
                          contentPadding: _fieldPadding,
                        ),
                      ),
                    ),
                  ),
                  SizedBox(
                    width: SettloSpacing.x2,
                    height: largeText ? SettloSpacing.x2 : 0,
                  ),
                  field(
                    width: 88,
                    child: _Labelled(
                      label: 'DUE DAY',
                      child: ios
                          ? _PickerField(
                              value: ordinal(_dueDay),
                              semanticLabel: 'Due day ${ordinal(_dueDay)}',
                              onTap: installment == null ? null : _pickDueDay,
                            )
                          : DropdownButtonFormField<int>(
                              initialValue: _dueDay,
                              isExpanded: true,
                              decoration: const InputDecoration(
                                contentPadding: _fieldPadding,
                              ),
                              icon: LoanGlyph(
                                LoanGlyph.chevronDown,
                                color: c.textSecondary,
                                size: 18,
                              ),
                              menuMaxHeight: 320,
                              items: [
                                for (var d = 1; d <= 28; d++)
                                  DropdownMenuItem(
                                    value: d,
                                    child: Text(
                                      ordinal(d),
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ),
                              ],
                              onChanged: installment == null
                                  ? null
                                  : (d) => setState(() => _dueDay = d!),
                            ),
                    ),
                  ),
                  SizedBox(
                    width: SettloSpacing.x2,
                    height: largeText ? SettloSpacing.x2 : 0,
                  ),
                  field(
                    width: 104,
                    child: _Labelled(
                      label: 'STARTS',
                      child: _PickerField(
                        value: monthYear(_start),
                        semanticLabel:
                            'Starts ${dayMonth(_start)} ${_start.year}',
                        onTap: _pickStart,
                      ),
                    ),
                  ),
                ],
              ),
              if (badInstallment) ...[
                const SizedBox(height: 8),
                Text(
                  'The monthly amount must be more than ₹0 and at most the '
                  'principal.',
                  style: SettloTypography.subheadline(color: c.textPrimary),
                ),
              ],
              gap,
              const _Interest(),
            ],
          ),
          action: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Above the button, so it is seen whatever is scrolled.
              if (_error case final error?) ...[
                Text(
                  error,
                  textAlign: TextAlign.center,
                  style: SettloTypography.subheadline(color: c.error),
                ),
                const SizedBox(height: SettloSpacing.x2),
              ],
              Text(
                '${first ?? 'They'} ${first == null ? 'get' : 'gets'} a '
                'WhatsApp message.$schedule\nSettlo keeps the record. It is '
                'not a lender and never moves money.',
                textAlign: TextAlign.center,
                style: SettloTypography.footnote(color: c.textMuted)
                    .copyWith(height: 1.5),
              ),
              const SizedBox(height: SettloSpacing.x2),
              SPrimaryButton(
                label: _busy ? 'Creating…' : 'Create loan and share',
                icon: Builder(
                  builder: (context) => LoanGlyph(
                    LoanGlyph.arrow,
                    color: IconTheme.of(context).color!,
                    size: 18,
                    stroke: 1.9,
                  ),
                ),
                onPressed: _busy || loan == null ? null : () => _create(loan),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// I lent money / I borrowed: the selected side lifted in primary text,
/// never gold (n21).
class _Direction extends StatelessWidget {
  const new({required this.youLent, required this.onChanged});

  final bool youLent;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    final c = SettloColors.of(context);
    if (Theme.of(context).platform == TargetPlatform.iOS) {
      return SSegmentedControl<bool>(
        segments: const [
          (value: true, label: 'I lent money'),
          (value: false, label: 'I borrowed'),
        ],
        selected: youLent,
        onChanged: onChanged,
      );
    }
    return Container(
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(
        color: c.surfaceRaised,
        border: Border.all(color: c.hairline),
        borderRadius: BorderRadius.circular(SettloRadius.button),
      ),
      child: Row(
        children: [
          for (final (lent, label) in [
            (true, 'I lent money'),
            (false, 'I borrowed'),
          ])
            Expanded(
              child: SPressable(
                onTap: () => onChanged(lent),
                selected: lent == youLent,
                ringRadius: BorderRadius.circular(SettloRadius.compact),
                child: Container(
                  constraints: const BoxConstraints(
                    minHeight: SettloSpacing.minTouchTarget,
                  ),
                  padding: const EdgeInsets.symmetric(
                    horizontal: SettloSpacing.x2,
                    vertical: SettloSpacing.x1,
                  ),
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: lent == youLent ? c.textPrimary : null,
                    borderRadius: BorderRadius.circular(SettloRadius.compact),
                  ),
                  child: FittedBox(
                    fit: BoxFit.scaleDown,
                    child: Text(
                      label,
                      maxLines: 1,
                      style: SettloTypography.body(
                        weight: lent == youLent
                            ? FontWeight.w500
                            : FontWeight.w400,
                        color: lent == youLent ? c.background : c.textSecondary,
                      ),
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// A field showing [value] that opens a picker; null [onTap] disables it.
class _PickerField extends StatelessWidget {
  const new({
    required this.value,
    required this.semanticLabel,
    required this.onTap,
  });

  final String value;
  final String semanticLabel;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) => SPressable(
    onTap: onTap,
    label: semanticLabel,
    ringRadius: BorderRadius.circular(SettloRadius.button),
    child: InputDecorator(
      decoration: InputDecoration(
        enabled: onTap != null,
        contentPadding: _fieldPadding,
      ),
      child: Text(
        value,
        maxLines: 1,
        softWrap: false,
        overflow: TextOverflow.fade,
        style: SettloTypography.headline(
          color: onTap == null
              ? SettloColors.of(context).textMuted
              : SettloColors.of(context).textPrimary,
        ),
      ),
    ),
  );
}

/// A small-caps label over a field.
class _Labelled extends StatelessWidget {
  const new({required this.label, required this.child});

  final String label;
  final Widget child;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      ExcludeSemantics(
        child: Text(
          label,
          maxLines: 1,
          style: SettloTypography.footnote(
            letterSpacing: 0.3,
            color: SettloColors.of(context).textSecondary,
          ),
        ),
      ),
      const SizedBox(height: SettloSpacing.x1),
      Semantics(label: label.toLowerCase(), child: child),
    ],
  );
}

/// The person picked; tap to change them.
class _Person extends StatelessWidget {
  const new({required this.who, required this.onChange});

  final ({String phone, String name}) who;
  final VoidCallback onChange;

  @override
  Widget build(BuildContext context) {
    final c = SettloColors.of(context);
    final named = who.name != groupPhone(who.phone);
    return SPressable(
      onTap: onChange,
      label: 'Change ${who.name}',
      ringRadius: BorderRadius.circular(SettloRadius.button),
      child: Container(
        constraints: const BoxConstraints(minHeight: 50),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        decoration: BoxDecoration(
          color: c.surfaceRaised,
          border: Border.all(color: c.hairline),
          borderRadius: BorderRadius.circular(SettloRadius.button),
        ),
        child: Row(
          children: [
            SAvatar(who.name, size: 30),
            const SizedBox(width: SettloSpacing.x2),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    who.name,
                    style: SettloTypography.headline(color: c.textPrimary),
                  ),
                  if (named)
                    Text(
                      groupPhone(who.phone),
                      style: SettloTypography.subheadline(
                        color: c.textSecondary,
                      ),
                    ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            LoanGlyph(LoanGlyph.person, color: c.textSecondary, size: 18),
          ],
        ),
      ),
    );
  }
}

/// Interest is off in v1, with the way to add it later shown (n21).
class _Interest extends StatelessWidget {
  const new();

  @override
  Widget build(BuildContext context) {
    final c = SettloColors.of(context);
    return MergeSemantics(
      child: Container(
        padding: const EdgeInsets.fromLTRB(16, 12, 12, 12),
        decoration: BoxDecoration(
          color: c.surfaceRaised,
          border: Border.all(color: c.hairline),
          borderRadius: BorderRadius.circular(SettloRadius.button),
        ),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Interest',
                    style: SettloTypography.body(color: c.textPrimary),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    'Interest free · add simple or reducing later',
                    style: SettloTypography.footnote(color: c.textSecondary),
                  ),
                ],
              ),
            ),
            const SSwitch(value: false, onChanged: null),
          ],
        ),
      ),
    );
  }
}

/// What WhatsApp is opened with: fixed trust copy and the capability link.
/// No amount or terms reach the number before it verifies (n43).
String loanInviteText(String? yourName, Uri link) {
  final name = yourName?.trim() ?? '';
  return '${name.isEmpty ? 'Hi' : 'Hi, this is $name'}. I recorded a loan '
      'between us on Settlo. You will see it in Settlo once you verify this '
      'number. $link';
}

/// The schedule fields' padding, narrower than the theme's so three fit
/// across 360.
const _fieldPadding = EdgeInsets.symmetric(horizontal: 12, vertical: 16);

/// Rupees as typed: up to nine digits, commas allowed, two decimals.
final _rupees = RegExp(r'^[\d,]{0,11}(\.\d{0,2})?$');
