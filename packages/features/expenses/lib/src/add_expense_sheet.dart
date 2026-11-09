import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:settlo_core/settlo_core.dart';

const _categories = ['Groceries', 'Utilities', 'Food'];

const _months = [
  'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', //
  'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
];

/// New expense in [space] (AddExpense artboard, canvas note n13): the
/// amount first in the serif, what for, who paid, and how it splits.
///
/// Defaults are you paid, split equally between everyone, today. Splits
/// are computed by the `packages/core` money functions and checked live;
/// Save stays off until they add up to the amount. The idempotency key is
/// made once when the sheet opens and sent with every attempt, so saving
/// again after a dropped connection never records it twice.
class AddExpenseSheet extends ConsumerStatefulWidget {
  /// The sheet for [space].
  const new({
    required this.space,
    required this.onClose,
    required this.onSaved,
    super.key,
  });

  /// Where the expense goes.
  final SpaceSummary space;

  /// Called by the close button.
  final VoidCallback onClose;

  /// Called once the expense is recorded.
  final VoidCallback onSaved;

  @override
  ConsumerState<AddExpenseSheet> createState() => _AddExpenseSheetState();
}

class _AddExpenseSheetState extends ConsumerState<AddExpenseSheet> {
  final String _key = newIdempotencyKey();
  late final List<SpaceMember> _members = [
    widget.space.you,
    ...widget.space.others,
  ];
  final _amount = TextEditingController();
  final _description = TextEditingController();
  String? _category;
  DateTime? _spentOn;
  late String _payer = widget.space.you.id;
  bool _multiPayer = false;
  SplitType _type = SplitType.equal;
  late final Set<String> _included = {for (final m in _members) m.id};

  /// Per-member inputs: what they paid (null type) or their split.
  final _fields = <(SplitType?, String), TextEditingController>{};
  String? _error;
  bool _saving = false;

  @override
  void dispose() {
    _amount.dispose();
    _description.dispose();
    for (final f in _fields.values) {
      f.dispose();
    }
    super.dispose();
  }

  TextEditingController _field(SplitType? type, String memberId) =>
      _fields.putIfAbsent((type, memberId), TextEditingController.new);

  String _name(SpaceMember m) => m.isYou ? 'You' : m.name;

  /// Who paid what; `problem` says why it does not match [total].
  ({Map<String, Paise> paid, String? problem}) _payers(Paise total) {
    if (!_multiPayer) return (paid: {_payer: total}, problem: null);
    final paid = {
      for (final m in _members)
        if (parseInr(_field(null, m.id).text) case final p? when p.value > 0)
          m.id: p,
    };
    final left = total - paid.values.fold(Paise.zero, (a, b) => a + b);
    return (paid: paid, problem: left.value == 0 ? null : _gap(left));
  }

  /// Everyone's split; null with a `problem` while it does not add up.
  ({List<ExpenseSplit>? splits, String? problem}) _splits(
    Paise total,
    Set<String> payers,
  ) {
    // Odd paise go to the first person in the split who paid (docs/api.md).
    String taker(Iterable<String> ids) =>
        ids.firstWhere(payers.contains, orElse: () => ids.first);
    ExpenseSplit split(String id, Paise amount, {int? bp, int? shares}) =>
        (memberId: id, amount: amount, percentBp: bp, shares: shares);
    Map<String, T> typed<T>(T? Function(String) parse) => {
      for (final m in _members) m.id: ?parse(_field(_type, m.id).text),
    };

    switch (_type) {
      case SplitType.equal:
        final ids = [
          for (final m in _members)
            if (_included.contains(m.id)) m.id,
        ];
        if (ids.isEmpty) {
          return (splits: null, problem: 'Pick at least one person.');
        }
        return (
          splits: [
            for (final e in splitEqual(total, ids, payer: taker(ids)).entries)
              split(e.key, e.value),
          ],
          problem: null,
        );
      case SplitType.exact:
        final amounts = typed(
          (t) => switch (parseInr(t)) {
            final p? when p.value > 0 => p,
            _ => null,
          },
        );
        final left = total - amounts.values.fold(Paise.zero, (a, b) => a + b);
        if (left.value != 0) return (splits: null, problem: _gap(left));
        return (
          splits: [
            for (final e in splitExact(total, amounts).entries)
              split(e.key, e.value),
          ],
          problem: null,
        );
      case SplitType.percent:
        // Hundredths of a percent are basis points.
        final bp = typed(
          (t) => switch (parseInr(t)) {
            final p? when p.value > 0 => p.value,
            _ => null,
          },
        );
        final sum = bp.values.fold(0, (a, b) => a + b);
        if (sum != 10000) {
          return (
            splits: null,
            problem: 'Adds up to ${_percent(sum)}. It needs to make 100%.',
          );
        }
        final amounts = splitPercent(total, bp, payer: taker(bp.keys));
        return (
          splits: [
            for (final e in amounts.entries)
              split(e.key, e.value, bp: bp[e.key]),
          ],
          problem: null,
        );
      case SplitType.shares:
        final shares = typed(
          (t) => switch (int.tryParse(t)) {
            final n? when n > 0 => n,
            _ => null,
          },
        );
        if (shares.isEmpty) {
          return (splits: null, problem: 'Give at least one person a share.');
        }
        final amounts = splitShares(total, shares, payer: taker(shares.keys));
        return (
          splits: [
            for (final e in amounts.entries)
              split(e.key, e.value, shares: shares[e.key]),
          ],
          problem: null,
        );
    }
  }

  static String _gap(Paise left) => left.value > 0
      ? '${formatInr(left)} still to assign.'
      : '${formatInr(-left)} more than the amount.';

  static String _percent(int bp) => bp % 100 == 0
      ? '${bp ~/ 100}%'
      : '${bp ~/ 100}.${(bp % 100).toString().padLeft(2, '0')}%';

  Future<void> _pickDate() async {
    final today = DateUtils.dateOnly(DateTime.now());
    final picked = await showDatePicker(
      context: context,
      initialDate: _spentOn ?? today,
      firstDate: DateTime(today.year - 1, today.month, today.day),
      lastDate: today,
    );
    if (picked == null) return;
    setState(() => _spentOn = picked == today ? null : picked);
  }

  Future<void> _save(NewExpense expense) async {
    setState(() {
      _saving = true;
      _error = null;
    });
    final ledger = ref.read(ledgerRevisionProvider.notifier);
    try {
      await ref
          .read(expensesRepositoryProvider)
          .add(expense, idempotencyKey: _key);
      ledger.bump();
      widget.onSaved();
    } on IdempotencyConflict {
      ledger.bump();
      _error =
          'This expense was already saved with the details you first '
          'entered. Close this to see it.';
    } on ExpenseRejected {
      _error =
          "This expense doesn't match the space any more. Someone may have "
          'left. Check who paid and who it is split with, then save again.';
    } on Exception {
      _error =
          "We couldn't save the expense. Check your connection and try "
          "again. It won't be recorded twice.";
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = SettloColors.of(context);
    final total = parseInr(_amount.text) ?? Paise.zero;
    final (:paid, problem: payersProblem) = _payers(total);
    final (:splits, problem: splitProblem) = _splits(total, paid.keys.toSet());
    final amountOf = {
      for (final s in splits ?? <ExpenseSplit>[]) s.memberId: s.amount,
    };
    final description = _description.text.trim();
    final ready =
        total.value > 0 &&
        description.isNotEmpty &&
        payersProblem == null &&
        splits != null;
    final label = _sectionLabel(c);
    final note = SettloTypography.figtree(12, color: c.textMuted);

    return SAmountSheet(
      title: 'New expense · ${widget.space.name}',
      onClose: widget.onClose,
      amount: Builder(
        builder: (context) {
          final style = DefaultTextStyle.of(context).style;
          return IntrinsicWidth(
            child: Semantics(
              label: 'Amount in rupees',
              child: TextField(
                controller: _amount,
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                ),
                inputFormatters: [_Rupees()],
                onChanged: (_) => setState(() {}),
                style: style,
                cursorColor: c.textPrimary,
                // No box: the amount is bare type, as on the canvas.
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
            label: 'What for',
            child: TextField(
              controller: _description,
              textCapitalization: TextCapitalization.sentences,
              onChanged: (_) => setState(() {}),
              style: SettloTypography.figtree(15, color: c.textPrimary),
              decoration: const InputDecoration(
                hintText: 'What for',
                contentPadding: EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 15,
                ),
              ),
            ),
          ),
          const SizedBox(height: 6),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              spacing: SettloSpacing.x1,
              children: [
                for (final category in _categories)
                  SChip(
                    label: category,
                    selected: _category == category,
                    onSelected: (on) =>
                        setState(() => _category = on ? category : null),
                  ),
                SChip(
                  label: switch (_spentOn) {
                    null => 'Today',
                    final d => '${d.day} ${_months[d.month - 1]}',
                  },
                  selected: _spentOn != null,
                  onSelected: (_) => _pickDate(),
                ),
              ],
            ),
          ),
          const SizedBox(height: 18),
          Text('PAID BY', style: label),
          const SizedBox(height: SettloSpacing.x1),
          Row(
            spacing: SettloSpacing.x1,
            children: [
              for (final m in _members.take(3))
                Expanded(
                  child: _Option(
                    label: _name(m),
                    selected: !_multiPayer && _payer == m.id,
                    onTap: () => setState(() {
                      _multiPayer = false;
                      _payer = m.id;
                    }),
                  ),
                ),
              _Option(
                label: '+',
                semanticLabel: 'Multiple payers',
                width: 46,
                selected: _multiPayer,
                onTap: () => setState(() => _multiPayer = !_multiPayer),
              ),
            ],
          ),
          if (_multiPayer) ...[
            const SizedBox(height: SettloSpacing.x1),
            for (final (i, m) in _members.indexed)
              _Line(
                divider: i < _members.length - 1,
                children: [
                  Expanded(child: _Name(_name(m))),
                  _Input(
                    key: ValueKey<(SplitType?, String)>((null, m.id)),
                    controller: _field(null, m.id),
                    semanticLabel: '${_name(m)} paid, in rupees',
                    hint: '₹0',
                    formatter: _Rupees(),
                    onChanged: () => setState(() {}),
                  ),
                ],
              ),
            if (payersProblem != null && total.value > 0)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text(payersProblem, style: note),
              ),
          ],
          const SizedBox(height: 18),
          Row(
            children: [
              Expanded(child: Text('SPLIT', style: label)),
              SSegmentedControl<SplitType>(
                segments: const [
                  (value: SplitType.equal, label: 'Equally'),
                  (value: SplitType.exact, label: 'Exact'),
                  (value: SplitType.percent, label: '%'),
                  (value: SplitType.shares, label: 'Shares'),
                ],
                selected: _type,
                onChanged: (type) => setState(() => _type = type),
              ),
            ],
          ),
          const SizedBox(height: 4),
          for (final (i, m) in _members.indexed)
            _splitRow(m, amountOf[m.id], divider: i < _members.length - 1),
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Text(switch (_type) {
              SplitType.equal when splitProblem == null =>
                'Odd paise go to whoever paid.',
              _ when splitProblem != null && total.value > 0 => splitProblem,
              _ => '',
            }, style: note),
          ),
          const SizedBox(height: SettloSpacing.x2),
        ],
      ),
      action: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          if (_error case final error?)
            Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: Text(
                error,
                style: SettloTypography.figtree(13, color: c.textPrimary),
              ),
            ),
          SizedBox(
            height: 54,
            child: SPrimaryButton(
              label: _saving ? 'Saving…' : 'Save expense',
              icon: ExpenseGlyph(ExpenseGlyph.check, color: c.onAction),
              onPressed: ready && !_saving
                  ? () => _save((
                      spaceId: widget.space.id,
                      description: description,
                      category: _category?.toLowerCase(),
                      amount: total,
                      spentOn: _spentOn,
                      splitType: _type,
                      payers: paid,
                      splits: splits,
                    ))
                  : null,
            ),
          ),
        ],
      ),
    );
  }

  Widget _splitRow(SpaceMember m, Paise? amount, {required bool divider}) {
    final name = _name(m);
    if (_type == SplitType.equal) {
      final on = _included.contains(m.id);
      void toggle() =>
          setState(() => on ? _included.remove(m.id) : _included.add(m.id));
      return MergeSemantics(
        child: InkWell(
          onTap: toggle,
          child: _Line(
            divider: divider,
            children: [
              Checkbox(
                value: on,
                onChanged: (_) => toggle(),
                materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                visualDensity: VisualDensity.compact,
              ),
              const SizedBox(width: 4),
              Expanded(child: _Name(name)),
              if (amount != null) MoneyText(amount, size: 14),
            ],
          ),
        ),
      );
    }
    final (hint, unit, formatter) = switch (_type) {
      SplitType.exact => ('₹0', 'in rupees', _Rupees()),
      SplitType.percent => (
        '0%',
        'percent',
        _Matching(RegExp(r'^\d{0,3}(\.\d{0,2})?$')),
      ),
      _ => ('0', 'shares', _Matching(RegExp(r'^\d{0,3}$'))),
    };
    return _Line(
      divider: divider,
      children: [
        Expanded(child: _Name(name)),
        if (_type != SplitType.exact && amount != null)
          MoneyText(amount, size: 13, tone: MoneyTone.settled),
        const SizedBox(width: 12),
        _Input(
          // Keyed by type: each split type keeps its own entries.
          key: ValueKey<(SplitType?, String)>((_type, m.id)),
          controller: _field(_type, m.id),
          semanticLabel: '$name, $unit',
          hint: hint,
          formatter: formatter,
          onChanged: () => setState(() {}),
        ),
      ],
    );
  }
}

/// Small-caps section labels: 12, tracked, secondary.
TextStyle _sectionLabel(SettloColors c) =>
    SettloTypography.figtree(12, letterSpacing: 0.3, color: c.textSecondary);

/// A split or payer row: at least 44 high, hairline below unless last.
class _Line extends StatelessWidget {
  const new({required this.children, required this.divider});

  final List<Widget> children;
  final bool divider;

  @override
  Widget build(BuildContext context) => Container(
    constraints: const BoxConstraints(minHeight: SettloSpacing.minTouchTarget),
    padding: const EdgeInsets.symmetric(vertical: 3),
    decoration: divider
        ? BoxDecoration(
            border: Border(
              bottom: BorderSide(color: SettloColors.of(context).hairline),
            ),
          )
        : null,
    child: Row(children: children),
  );
}

class _Name extends StatelessWidget {
  const new(this.name);

  final String name;

  @override
  Widget build(BuildContext context) => Text(
    name,
    maxLines: 1,
    overflow: TextOverflow.ellipsis,
    style: SettloTypography.figtree(
      14,
      color: SettloColors.of(context).textPrimary,
    ),
  );
}

/// A small right-aligned number field in a row.
class _Input extends StatelessWidget {
  const new({
    required this.controller,
    required this.semanticLabel,
    required this.hint,
    required this.formatter,
    required this.onChanged,
    super.key,
  });

  final TextEditingController controller;
  final String semanticLabel;
  final String hint;
  final TextInputFormatter formatter;
  final VoidCallback onChanged;

  @override
  Widget build(BuildContext context) => SizedBox(
    width: 96,
    child: Semantics(
      label: semanticLabel,
      child: TextField(
        controller: controller,
        textAlign: TextAlign.end,
        keyboardType: const TextInputType.numberWithOptions(decimal: true),
        inputFormatters: [formatter],
        onChanged: (_) => onChanged(),
        style: SettloTypography.figtree(
          14,
          weight: FontWeight.w500,
          color: SettloColors.of(context).textPrimary,
        ),
        decoration: InputDecoration(
          hintText: hint,
          isDense: true,
          contentPadding: const EdgeInsets.symmetric(
            horizontal: 12,
            vertical: 12,
          ),
        ),
      ),
    ),
  );
}

/// A payer option: 46 high, radius 14; the chosen one is inverted, never
/// gold (choosing is not the primary action).
class _Option extends StatelessWidget {
  const new({
    required this.label,
    required this.selected,
    required this.onTap,
    this.semanticLabel,
    this.width,
  });

  final String label;
  final String? semanticLabel;
  final bool selected;
  final VoidCallback onTap;
  final double? width;

  @override
  Widget build(BuildContext context) {
    final c = SettloColors.of(context);
    final radius = BorderRadius.circular(14);
    return Semantics(
      button: true,
      selected: selected,
      label: semanticLabel ?? label,
      excludeSemantics: true,
      child: Material(
        color: selected ? c.textPrimary : c.surfaceRaised,
        shape: RoundedRectangleBorder(
          borderRadius: radius,
          side: selected ? BorderSide.none : BorderSide(color: c.hairline),
        ),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: Container(
            height: 46,
            width: width,
            alignment: Alignment.center,
            padding: const EdgeInsets.symmetric(horizontal: 8),
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: SettloTypography.figtree(
                label == '+' ? 16 : 14,
                weight: selected ? FontWeight.w500 : FontWeight.w400,
                color: selected ? c.background : c.textPrimary,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Rupees as typed, grouped the Indian way (`1,80,000.5`), at most two
/// decimals. shortcut: the cursor jumps to the end on every edit; keep it
/// in place if mid-number edits turn out to matter.
class _Rupees extends TextInputFormatter {
  static final _typed = RegExp(r'^(\d{0,9})(\.\d{0,2})?$');

  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    final m = _typed.firstMatch(newValue.text.replaceAll(',', ''));
    if (m == null) return oldValue;
    final whole = m[1]!;
    final grouped = whole.isEmpty
        ? ''
        : formatInr(Paise.rupees(int.parse(whole))).substring(1);
    final text = '$grouped${m[2] ?? ''}';
    return TextEditingValue(
      text: text,
      selection: TextSelection.collapsed(offset: text.length),
    );
  }
}

/// Accepts an edit only while the whole text matches [pattern].
class _Matching extends TextInputFormatter {
  const new(this.pattern);

  final RegExp pattern;

  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) => pattern.hasMatch(newValue.text) ? newValue : oldValue;
}

/// A canvas line icon in a 24 box, drawn as round-capped strokes.
class ExpenseGlyph extends StatelessWidget {
  /// [lines] in [color] at [size], [stroke] wide in the 24 box.
  const new(
    this.lines, {
    required this.color,
    this.size = 18,
    this.stroke = 1.9,
    super.key,
  });

  /// The tick on Save expense (`M5 12l5 5L20 7`).
  static const check = [
    [Offset(5, 12), Offset(10, 17), Offset(20, 7)],
  ];

  /// The close cross (`M6 6l12 12M18 6L6 18`).
  static const close = [
    [Offset(6, 6), Offset(18, 18)],
    [Offset(18, 6), Offset(6, 18)],
  ];

  /// Polylines in the 24 box.
  final List<List<Offset>> lines;

  /// Stroke colour.
  final Color color;

  /// Rendered size.
  final double size;

  /// Stroke width in the 24 box.
  final double stroke;

  @override
  Widget build(BuildContext context) => CustomPaint(
    size: Size.square(size),
    painter: _GlyphPainter(lines, color, stroke),
  );
}

class _GlyphPainter extends CustomPainter {
  const new(this.lines, this.color, this.stroke);

  final List<List<Offset>> lines;
  final Color color;
  final double stroke;

  @override
  void paint(Canvas canvas, Size size) {
    final scale = size.width / 24;
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = stroke * scale
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;
    for (final line in lines) {
      canvas.drawPath(
        Path()..addPolygon([for (final p in line) p * scale], false),
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(_GlyphPainter old) =>
      old.color != color || old.lines != lines || old.stroke != stroke;
}
