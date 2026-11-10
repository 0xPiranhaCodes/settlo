import 'dart:async';

import 'package:settlo_core/settlo_core.dart';
import 'package:settlo_local/src/db.dart';
import 'package:settlo_local/src/overlay.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Writes whose keys the server forgets 30 days after first use (#70). One
/// first sent longer ago is dropped a day early rather than risk applying
/// twice.
const _purgedKinds = {
  'update_expense',
  'delete_expense',
  'confirm_settlement',
  'dispute_settlement',
  'confirm_repayment',
  'dispute_repayment',
  'accept_claim',
  'reject_claim',
};

const _loanKinds = {
  'create_loan',
  'record_repayment',
  'confirm_repayment',
  'dispute_repayment',
};

/// PostgREST's `max_rows` (supabase/config.toml): a read that returns
/// this many rows may have been cut short.
const mirrorPageSize = 1000;

/// How many feed entries the mirror keeps: `activity_feed`'s largest page.
const mirroredActivity = 100;

/// Replays one signed-in user's queue and refreshes their mirror
/// (ADR 0004; design on #53).
///
/// [sync] is single-flight: it replays every queued write in order, one
/// at a time, with its stored key, then refreshes the mirror from the
/// server, but only once nothing is left unsent, so a write whose response
/// was lost is never counted both in fresh rows and in the queue.
final class SyncEngine {
  /// Syncs [owner]'s rows in [_db] through [_client].
  new(
    this._db,
    this._client, {
    required this.owner,
    this.onChanged,
    this.now = DateTime.now,
    this.submitWait = const Duration(seconds: 5),
    this.pageSize = mirrorPageSize,
  }) : _session = _db.session;

  final LocalDb _db;
  final SupabaseClient _client;

  /// The signed-in user's id; every row read or written is theirs.
  final String owner;

  /// Called after a sync changed what the mirror shows.
  final void Function()? onChanged;

  /// The clock.
  final DateTime Function() now;

  /// How long [submit] waits for the server before leaving the write
  /// queued.
  final Duration submitWait;

  /// The server's row cap per read; see [fetchMirror].
  final int pageSize;

  final _notices = StreamController<String>.broadcast();
  final _waiting = <String, Completer<String?>>{};
  Future<void>? _running;
  var _again = false;
  var _changed = false;
  final _cancelled = Completer<void>();

  /// The database's session when this engine was made.
  final (String?, int) _session;

  /// Signed out, or the database was wiped since: nothing this engine
  /// still has in flight may be written.
  bool get _stale => _cancelled.isCompleted || _db.session != _session;

  /// Runs [write] in a transaction unless [_stale]; false when it did not
  /// run. Checked inside the transaction, so a wipe that began while
  /// [write] waited for the database is seen.
  Future<bool> _write(Future<void> Function() write) =>
      _db.transaction(() async {
        if (_stale) return false;
        await write();
        return true;
      });
  Timer? _retry;

  /// Plain sentences about writes the server refused after the screen
  /// that made them had moved on.
  Stream<String> get notices => _notices.stream;

  /// The mirror with every queued write applied, as of [today]: only this
  /// month's fairness and categories.
  Future<Tables> snapshot(DateTime today) async {
    final t = await _db.mirror(owner);
    final month = dateKey(DateTime(today.year, today.month));
    for (final view in ['space_monthly_fairness', 'space_monthly_categories']) {
      t[view] = [...?t[view]?.where((r) => r['month'] == month)];
    }
    return applyQueue(
      t,
      await _db.mutations(owner),
      userId: owner,
      today: today,
    );
  }

  /// How many queued writes the server has not taken yet. Signing out
  /// deletes them.
  Future<int> unsent() => _db.unsent(owner);

  /// Queues [kind] with [params] under [key] and returns the server's id,
  /// or `local:<key>` when the server has not answered within
  /// [submitWait]; the write then shows from the queue. A refusal in that
  /// time is rolled back and thrown as the repositories' exceptions.
  Future<String> submit(
    String kind,
    Map<String, Object?> params,
    String key,
  ) async {
    if (!await _write(() => _db.enqueue(owner, key, kind, params, now()))) {
      throw const SessionEnded();
    }
    final done = _waiting[key] = Completer<String?>();
    unawaited(sync());
    try {
      return await done.future.timeout(submitWait) ?? 'local:$key';
    } on TimeoutException {
      return 'local:$key';
    } finally {
      _waiting.remove(key);
    }
  }

  /// Replays the queue, then refreshes the mirror. A call while one runs
  /// runs it again after.
  Future<void> sync() {
    if (_running case final running?) {
      _again = true;
      return running;
    }
    return _running = _loop().whenComplete(() => _running = null);
  }

  Future<void> _loop() async {
    do {
      _again = false;
      if (await _replay() && !_stale) await _refresh();
    } while (_again && !_stale);
    if (_changed && !_stale) onChanged?.call();
    _changed = false;
  }

  /// Sends every unsent write; true when none is left.
  Future<bool> _replay() async {
    final ids = await _db.localIds(owner);
    for (final m in await _db.mutations(owner)) {
      if (_stale) return false;
      if (m.applied) continue;
      if (m.firstAttemptAt case final first?
          when _purgedKinds.contains(m.kind) &&
              now().difference(first) > const Duration(days: 29)) {
        await _reject(m, const PostgrestException(message: '', code: 'stale'));
        continue;
      }
      try {
        if (!await _write(() => _db.markAttempted(m.id, now()))) return false;
        // Signing out stops waiting for the answer; whatever it is, it is
        // dropped.
        final result = await Future.any<Object?>([
          _client.rpc<Object?>(
            m.kind,
            params: _resolve(m.params, ids)! as Map<String, dynamic>,
          ),
          _cancelled.future,
        ]);
        if (_stale) return false;
        final created = await _created(m, result);
        if (!await _write(() => _db.markApplied(owner, m.id, created))) {
          return false;
        }
        ids.addAll(created);
        _changed = true;
        _waiting[m.key]?.complete(result is String ? result : null);
      } on Exception catch (e) {
        if (e is PostgrestException && _refused(e)) {
          await _reject(m, e);
          continue;
        }
        if (!await _write(() => _db.markFailed(m.id, '$e'))) return false;
        _waiting[m.key]?.complete(null);
        _retryIn(Duration(seconds: 2 << m.attempts.clamp(0, 5)));
        return false;
      }
    }
    return true;
  }

  /// The local ids [m] created, mapped to the server's.
  Future<Map<String, String>> _created(Mutation m, Object? result) async {
    switch (m.kind) {
      case 'add_expense':
        return {'local:${m.key}': result! as String};
      case 'create_space':
        final rows = await _client
            .from('space_members')
            .select('id, phone, user_id')
            .eq('space_id', m.key);
        return {
          for (final r in rows)
            'local:${m.key}:${r['user_id'] == owner ? 'me' : r['phone']}':
                r['id'] as String,
        };
    }
    return const {};
  }

  /// [value] with every device-made id replaced by the server's. One
  /// with no server id belongs to a write that was refused.
  Object? _resolve(Object? value, Map<String, String> ids) => switch (value) {
    final String s when s.startsWith('local:') =>
      ids[s] ?? (throw const PostgrestException(message: '', code: 'orphan')),
    final Map<String, dynamic> map => {
      for (final MapEntry(:key, :value) in map.entries)
        key: _resolve(value, ids),
    },
    final List<dynamic> list => [for (final v in list) _resolve(v, ids)],
    _ => value,
  };

  /// The server refused the write itself: retrying cannot help.
  static bool _refused(PostgrestException e) => switch (e.code) {
    'PT409' || '42501' || 'orphan' => true,
    final String code => code.startsWith('22') || code.startsWith('23'),
    null => false,
  };

  /// Drops [m], which rolls it back, and tells whoever made it.
  Future<void> _reject(Mutation m, PostgrestException e) async {
    if (!await _write(() => _db.drop(m.id))) return;
    _changed = true;
    final waiting = _waiting.remove(m.key);
    if (waiting != null) {
      waiting.completeError(_exception(m.kind, e));
    } else {
      _notices.add(rejection(m, e));
    }
  }

  static Exception _exception(String kind, PostgrestException e) =>
      switch ((e.code, e.hint)) {
        ('PT409', _) => const IdempotencyConflict(),
        (_, 'settlement_pending') => const SettlementPending(),
        (_, 'settlement_changed') => const SettlementChanged(),
        ('22023', _) when kind == 'add_expense' => const ExpenseRejected(),
        _ when _loanKinds.contains(kind) => loanRefusal(e),
        _ => e,
      };

  Future<void> _refresh() async {
    final Tables tables;
    try {
      tables = await fetchMirror(_client, now(), pageSize: pageSize);
    } on Exception {
      _retryIn(const Duration(seconds: 2));
      return;
    }
    await _write(() async {
      if (await _db.replaceMirror(owner, tables)) _changed = true;
    });
    if (_stale) return;
    _retry?.cancel();
  }

  void _retryIn(Duration delay) {
    if (_stale) return;
    _retry?.cancel();
    _retry = Timer(delay, () => unawaited(sync()));
  }

  /// Stops syncing: a request in flight is no longer waited for, and a
  /// sync in flight writes nothing more.
  void dispose() {
    if (_cancelled.isCompleted) return;
    _cancelled.complete();
    _retry?.cancel();
    unawaited(_notices.close());
  }
}

/// Plain copy for refused write [m] (`voice` in the context pack).
String rejection(Mutation m, PostgrestException e) {
  final p = (m.params['p'] as Map<String, dynamic>?) ?? m.params;
  final what = switch (m.kind) {
    'add_expense' =>
      '“${p['description']}” (${formatInr(Paise(p['amount_minor'] as int))})',
    'update_expense' => 'Your edit to “${p['description']}”',
    'delete_expense' => 'Deleting that expense',
    'create_space' => 'The space “${p['p_name']}”',
    'confirm_settlement' => 'Your confirmation of that settle-up',
    'dispute_settlement' => 'Your dispute of that settle-up',
    'create_loan' =>
      'Your loan of ${formatInr(Paise(p['principal_minor'] as int))}',
    'record_repayment' =>
      'Your repayment of ${formatInr(Paise(p['amount_minor'] as int))}',
    'confirm_repayment' => 'Your confirmation of that repayment',
    'dispute_repayment' => 'Your dispute of that repayment',
    'accept_claim' => 'Accepting that invite',
    'reject_claim' => 'Declining that invite',
    _ => 'A change',
  };
  final loan = _loanKinds.contains(m.kind);
  final why = switch ((e.code, e.hint)) {
    ('stale', _) => 'it waited too long to reach the server',
    ('orphan', _) => 'it depended on a change that wasn’t saved',
    ('PT409', _) => 'a different version of it was already saved',
    (_, 'departed_member') => 'someone in it has left the space',
    (_, 'settlement_pending') => 'a settle-up between you is already waiting',
    (_, 'settlement_changed') => 'the settle-up changed since you saw it',
    (_, 'settlement_final') => 'the settle-up was already answered',
    (_, 'overpayment') => 'it is more than is left on the loan',
    (_, 'loan_closed') => 'the loan is already fully repaid',
    (_, 'not_pending') => 'the repayment was already answered',
    ('42501', _) when m.kind.endsWith('_claim') =>
      'it was already answered or withdrawn',
    ('42501', _) when loan => 'you can’t change this loan any more',
    ('42501', _) => 'you can’t change this space any more',
    _ when loan => 'the details didn’t match the loan',
    _ => 'the details didn’t match the space',
  };
  return '$what couldn’t be saved because $why. '
      'We’ve undone it on this phone.';
}

/// One mirrored table or view: its rows, how they are ordered (the last
/// column makes the order total, so pages never overlap), and whether it
/// has a `space_id` to page by.
typedef _Source = ({
  PostgrestFilterBuilder<PostgrestList> Function() select,
  List<(String, {bool ascending})> order,
  bool bySpace,
});

/// Every row the offline repositories read, as RLS lets the caller see
/// them, with this month's views as of [today].
///
/// PostgREST cuts a read at `max_rows`, so a source that comes back
/// [pageSize] long is read again in full: space by space when it has a
/// `space_id`, and a page at a time within each.
// shortcut: pages are separate requests, so a row written between two of
// them can be missed or repeated until the next refresh; move to keyset
// pages if that shows.
Future<Tables> fetchMirror(
  SupabaseClient db,
  DateTime today, {
  int pageSize = mirrorPageSize,
}) async {
  final month = dateKey(DateTime(today.year, today.month));
  final sources = <String, _Source>{
    'space_members': (
      select: () => db
          .from('space_members')
          .select(
            'id, space_id, user_id, name, phone, role, accepted_at, left_at, '
            'created_at, spaces(name, kind, created_by, deleted_at)',
          ),
      order: [('created_at', ascending: true), ('id', ascending: true)],
      bySpace: true,
    ),
    'space_member_balances': (
      select: () => db
          .from('space_member_balances')
          .select('space_id, member_id, paid_minor, balance_minor'),
      order: [('member_id', ascending: true)],
      bySpace: true,
    ),
    'space_monthly_fairness': (
      select: () => db
          .from('space_monthly_fairness')
          .select(
            'space_id, month, member_id, paid_minor, fair_share_minor, '
            'month_total_minor',
          )
          .eq('month', month),
      order: [('member_id', ascending: true)],
      bySpace: true,
    ),
    'space_monthly_categories': (
      select: () => db
          .from('space_monthly_categories')
          .select('space_id, month, category, total_minor, expense_count')
          .eq('month', month),
      order: [('space_id', ascending: true), ('category', ascending: true)],
      bySpace: true,
    ),
    'pending_settlements': (
      select: () => db
          .from('pending_settlements')
          .select(
            'expense_id, space_id, payer_member_id, payee_member_id, '
            'amount_minor',
          ),
      order: [('expense_id', ascending: true)],
      bySpace: true,
    ),
    'expenses': (
      select: () => db
          .from('expenses')
          .select(
            'id, space_id, description, category, amount_minor, spent_on, '
            'is_settlement, settlement_status, dispute_reason, created_by, '
            'created_at, deleted_at, '
            'expense_payers(member_id, amount_minor), '
            'expense_splits(member_id, split_type, amount_minor, shares, '
            'percent_bp, space_members(created_at))',
          )
          .isFilter('deleted_at', null),
      order: [
        ('spent_on', ascending: false),
        ('created_at', ascending: false),
        ('id', ascending: true),
      ],
      bySpace: true,
    ),
    'profiles': (
      select: () => db.from('profiles').select('id, name, phone, upi_id'),
      order: [('id', ascending: true)],
      bySpace: false,
    ),
    'loans': (
      select: () => db
          .from('loans')
          .select(
            'id, lender_id, borrower_id, lender_phone, borrower_phone, '
            'lender_accepted_at, borrower_accepted_at, created_by, closed_at',
          ),
      order: [('created_at', ascending: true), ('id', ascending: true)],
      bySpace: false,
    ),
    'loan_summaries': (
      select: () => db
          .from('loan_summaries')
          .select(
            'loan_id, principal_minor, repaid_minor, outstanding_minor, '
            'installment_minor, due_day, start_on, closed_at, '
            'installments_total, installments_paid, next_due_on, ends_on, '
            'on_track',
          ),
      order: [('loan_id', ascending: true)],
      bySpace: false,
    ),
    'loan_repayments': (
      select: () => db
          .from('loan_repayments')
          .select(
            'id, loan_id, amount_minor, paid_on, method, reference, '
            'recorded_by, status, dispute_reason',
          ),
      order: [
        ('paid_on', ascending: false),
        ('created_at', ascending: false),
        ('id', ascending: true),
      ],
      bySpace: false,
    ),
    'needs_you': (
      select: () => db
          .from('needs_you')
          .select(
            'kind, id, space_id, space_name, loan_id, counterparty, '
            'amount_minor, paid_on, created_at',
          ),
      order: [('created_at', ascending: false), ('id', ascending: true)],
      bySpace: false,
    ),
  };

  PostgrestTransformBuilder<PostgrestList> query(_Source s, [String? space]) {
    PostgrestTransformBuilder<PostgrestList> q = space == null
        ? s.select()
        : s.select().eq('space_id', space);
    for (final (column, :ascending) in s.order) {
      q = q.order(column, ascending: ascending);
    }
    return q;
  }

  // Every row of [q], starting from its first page if already read.
  Future<PostgrestList> pages(
    PostgrestTransformBuilder<PostgrestList> Function() q, [
    PostgrestList? first,
  ]) async {
    final rows = [...?first];
    var last = first?.length ?? pageSize;
    while (last >= pageSize) {
      final page = await q().range(rows.length, rows.length + pageSize - 1);
      rows.addAll(page);
      last = page.length;
    }
    return rows;
  }

  Future<PostgrestList> read(_Source s) async {
    final first = await query(s);
    if (first.length < pageSize) return first;
    if (!s.bySpace) return await pages(() => query(s), first);
    final spaces = await pages(
      () => db.from('spaces').select('id').order('id'),
    );
    final rows = [
      for (final part in await Future.wait([
        for (final space in spaces)
          pages(() => query(s, space['id'] as String)),
      ]))
        ...part,
    ];
    // Back into the order one read would have given.
    return rows..sort((a, b) {
      for (final (column, :ascending) in s.order) {
        final by = '${a[column]}'.compareTo('${b[column]}');
        if (by != 0) return ascending ? by : -by;
      }
      return 0;
    });
  }

  final rows = await Future.wait([
    for (final s in sources.values) read(s),
    // A read-only function, so a GET: nothing here is a write.
    db
        .rpc<List<dynamic>>(
          'activity_feed',
          params: {'p_limit': mirroredActivity},
          get: true,
        )
        .then((rows) => rows.cast<Map<String, dynamic>>()),
  ]);
  return Map.fromIterables([...sources.keys, 'activity_feed'], rows);
}
