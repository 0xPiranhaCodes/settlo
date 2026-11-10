import 'package:settlo_core/export/names.dart';
import 'package:settlo_core/money/paise.dart';
import 'package:settlo_core/supabase/space_ledger.dart';
import 'package:settlo_core/supabase/spaces.dart';

/// [space]'s expenses as CSV, one row per member per expense, oldest
/// first: what each person paid and their share, in paise and in rupees.
///
/// Settle-ups are flagged with their status. Members appear by name only,
/// never by number ([exportNames]). The text starts with a byte order mark
/// so spreadsheet apps read Unicode names as UTF-8.
String spaceCsv(SpaceSummary space, SpaceLedger ledger) {
  final names = exportNames([...space.members, ...space.departed]);
  final rows = <List<String>>[
    [
      'entry', 'date', 'description', 'category', 'settlement', //
      'settlement_status', 'total_paise', 'total_rupees', 'member',
      'paid_paise', 'paid_rupees', 'share_paise', 'share_rupees',
    ],
  ];
  for (final (i, e) in ledger.expenses.reversed.indexed) {
    final paid = {for (final p in e.payers) p.memberId: p.amount};
    final share = {for (final s in e.splits) s.memberId: s.amount};
    // Split order is the space's member order; payers not split come after.
    final ids = {...share.keys, ...paid.keys};
    for (final id in ids) {
      rows.add([
        '${i + 1}',
        _date(e.spentOn),
        _text(e.description),
        _text(e.category ?? ''),
        if (e.isSettlement) 'yes' else 'no',
        e.settlementStatus?.name ?? '',
        '${e.amount.value}',
        _rupees(e.amount),
        _text(names[id] ?? 'Former member'),
        '${(paid[id] ?? Paise.zero).value}',
        _rupees(paid[id] ?? Paise.zero),
        '${(share[id] ?? Paise.zero).value}',
        _rupees(share[id] ?? Paise.zero),
      ]);
    }
  }
  return '\uFEFF${rows.map((r) => r.map(_field).join(',')).join('\r\n')}\r\n';
}

/// RFC 4180: quote a field holding a comma, quote or line break.
String _field(String v) =>
    v.contains(RegExp('[",\r\n]')) ? '"${v.replaceAll('"', '""')}"' : v;

/// Free text other members typed: a leading `=`, `+`, `-` or `@` would run
/// as a formula in a spreadsheet, so it is prefixed with `'`.
String _text(String v) => v.startsWith(RegExp('[=+\\-@\t\r]')) ? "'$v" : v;

/// `420.50`: plain decimal rupees a spreadsheet can sum.
String _rupees(Paise p) =>
    '${p.value ~/ 100}.${(p.value % 100).toString().padLeft(2, '0')}';

String _date(DateTime d) =>
    '${d.year.toString().padLeft(4, '0')}-'
    '${d.month.toString().padLeft(2, '0')}-'
    '${d.day.toString().padLeft(2, '0')}';
