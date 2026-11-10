import 'dart:io';

import 'package:settlo_core/export/names.dart';
import 'package:settlo_core/money/paise.dart';
import 'package:settlo_core/supabase/space_ledger.dart';
import 'package:settlo_core/supabase/spaces.dart';

/// [space]'s expenses as CSV lines (no line endings), header first, one row
/// per member per expense, oldest first: what each person paid and their
/// share, in paise and in rupees. Lazy, so a large ledger can be streamed
/// ([writeSpaceCsv]).
///
/// Settle-ups are flagged with their status. Members appear by name only
/// ([exportNames]), and phone numbers in free text are redacted
/// ([redactPhones]).
Iterable<String> spaceCsvLines(SpaceSummary space, SpaceLedger ledger) sync* {
  final names = exportNames([...space.members, ...space.departed]);
  yield const [
    'entry', 'date', 'description', 'category', 'settlement', //
    'settlement_status', 'total_paise', 'total_rupees', 'member',
    'paid_paise', 'paid_rupees', 'share_paise', 'share_rupees',
  ].join(',');
  for (final (i, e) in ledger.expenses.reversed.indexed) {
    final paid = {for (final p in e.payers) p.memberId: p.amount};
    final share = {for (final s in e.splits) s.memberId: s.amount};
    // Split order is the space's member order; payers not split come after.
    for (final id in {...share.keys, ...paid.keys}) {
      yield [
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
      ].map(_field).join(',');
    }
  }
}

/// [spaceCsvLines] as one string: a byte order mark, so spreadsheet apps
/// read Unicode names as UTF-8, then CRLF-terminated lines.
String spaceCsv(SpaceSummary space, SpaceLedger ledger) =>
    '﻿${spaceCsvLines(space, ledger).map((l) => '$l\r\n').join()}';

/// Streams [spaceCsv] to [file] line by line, never holding it whole.
Future<void> writeSpaceCsv(
  SpaceSummary space,
  SpaceLedger ledger,
  File file,
) async {
  final sink = file.openWrite()..write('﻿');
  try {
    for (final line in spaceCsvLines(space, ledger)) {
      sink.write('$line\r\n');
    }
  } finally {
    await sink.close();
  }
}

/// RFC 4180: quote a field holding a comma, quote or line break.
String _field(String v) =>
    v.contains(RegExp('[",\r\n]')) ? '"${v.replaceAll('"', '""')}"' : v;

/// Free text other members typed: numbers are redacted, and a leading `=`,
/// `+`, `-` or `@` would run as a formula in a spreadsheet, so it is
/// prefixed with `'`.
String _text(String v) {
  final t = redactPhones(v);
  return t.startsWith(RegExp('[=+\\-@\t\r]')) ? "'$t" : t;
}

/// `420.50`: plain decimal rupees a spreadsheet can sum.
String _rupees(Paise p) =>
    '${p.value ~/ 100}.${(p.value % 100).toString().padLeft(2, '0')}';

String _date(DateTime d) =>
    '${d.year.toString().padLeft(4, '0')}-'
    '${d.month.toString().padLeft(2, '0')}-'
    '${d.day.toString().padLeft(2, '0')}';
