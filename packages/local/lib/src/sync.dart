import 'dart:async';

import 'package:settlo_core/settlo_core.dart';
import 'package:settlo_local/src/db.dart';
import 'package:settlo_local/src/overlay.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Writes whose keys the server forgets after 30 days (#70). A sent one is
/// dropped a day early rather than risk applying twice.
const _purgedKinds = {
  'update_expense',
  'delete_expense',
  'confirm_settlement',
  'dispute_settlement',
};

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
  });

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

  final _notices = StreamController<String>.broadcast();
  final _waiting = <String, Completer<String?>>{};
  Future<void>? _running;
  var _again = false;
  var _changed = false;
  var _disposed = false;
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

  /// Queues [kind] with [params] under [key] and returns the server's id,
  /// or `local:<key>` when the server has not answered within
  /// [submitWait]; the write then shows from the queue. A refusal in that
  /// time is rolled back and thrown as the repositories' exceptions.
  Future<String> submit(
    String kind,
    Map<String, Object?> params,
    String key,
  ) async {
    await _db.enqueue(owner, key, kind, params, now());
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
      if (await _replay() && !_disposed) await _refresh();
    } while (_again && !_disposed);
    if (_changed && !_disposed) onChanged?.call();
    _changed = false;
  }

  /// Sends every unsent write; true when none is left.
  Future<bool> _replay() async {
    final ids = <String, Object?>{};
    for (final m in await _db.mutations(owner)) {
      if (_disposed) return false;
      if (m.applied) {
        ids.addAll(m.result);
        continue;
      }
      if (m.attempts > 0 &&
          _purgedKinds.contains(m.kind) &&
          now().difference(m.createdAt) > const Duration(days: 29)) {
        await _reject(m, const PostgrestException(message: '', code: 'stale'));
        continue;
      }
      try {
        final result = await _client.rpc<Object?>(
          m.kind,
          params: _resolve(m.params, ids)! as Map<String, dynamic>,
        );
        final created = await _created(m, result);
        await _db.markApplied(m.id, created);
        ids.addAll(created);
        _changed = true;
        _waiting[m.key]?.complete(result is String ? result : null);
      } on Exception catch (e) {
        if (e is PostgrestException && _refused(e)) {
          await _reject(m, e);
          continue;
        }
        await _db.markFailed(m.id, '$e');
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
  Object? _resolve(Object? value, Map<String, Object?> ids) => switch (value) {
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
    await _db.drop(m.id);
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
        _ => e,
      };

  Future<void> _refresh() async {
    final Tables tables;
    try {
      tables = await fetchMirror(_client, now());
    } on Exception {
      _retryIn(const Duration(seconds: 2));
      return;
    }
    if (_disposed) return;
    await _db.replaceMirror(owner, tables);
    _changed = true;
    _retry?.cancel();
  }

  void _retryIn(Duration delay) {
    if (_disposed) return;
    _retry?.cancel();
    _retry = Timer(delay, () => unawaited(sync()));
  }

  /// Stops syncing; a sync in flight writes nothing more.
  void dispose() {
    _disposed = true;
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
    _ => 'A change',
  };
  final why = switch ((e.code, e.hint)) {
    ('stale', _) => 'it waited too long to reach the server',
    ('orphan', _) => 'it depended on a change that wasn’t saved',
    ('PT409', _) => 'a different version of it was already saved',
    (_, 'departed_member') => 'someone in it has left the space',
    (_, 'settlement_pending') => 'a settle-up between you is already waiting',
    (_, 'settlement_changed') => 'the settle-up changed since you saw it',
    (_, 'settlement_final') => 'the settle-up was already answered',
    ('42501', _) => 'you can’t change this space any more',
    _ => 'the details didn’t match the space',
  };
  return '$what couldn’t be saved because $why. '
      'We’ve undone it on this phone.';
}

/// Every row the offline repositories read, as RLS lets the caller see
/// them, with this month's views as of [today].
// shortcut: PostgREST caps a read at max_rows (1000), so a user with more
// live expenses across their spaces sees the newest 1000; page by space
// when one gets there.
Future<Tables> fetchMirror(SupabaseClient db, DateTime today) async {
  final month = dateKey(DateTime(today.year, today.month));
  final sources = <String, Future<List<Map<String, dynamic>>>>{
    'space_members': db
        .from('space_members')
        .select(
          'id, space_id, user_id, name, phone, role, accepted_at, left_at, '
          'created_at, spaces(name, kind, created_by, deleted_at)',
        )
        .order('created_at'),
    'space_member_balances': db
        .from('space_member_balances')
        .select('space_id, member_id, paid_minor, balance_minor'),
    'space_monthly_fairness': db
        .from('space_monthly_fairness')
        .select(
          'space_id, month, member_id, paid_minor, fair_share_minor, '
          'month_total_minor',
        )
        .eq('month', month),
    'space_monthly_categories': db
        .from('space_monthly_categories')
        .select('space_id, month, category, total_minor, expense_count')
        .eq('month', month),
    'pending_settlements': db
        .from('pending_settlements')
        .select(
          'expense_id, space_id, payer_member_id, payee_member_id, '
          'amount_minor',
        ),
    'expenses': db
        .from('expenses')
        .select(
          'id, space_id, description, category, amount_minor, spent_on, '
          'is_settlement, settlement_status, dispute_reason, created_by, '
          'deleted_at, '
          'expense_payers(member_id, amount_minor), '
          'expense_splits(member_id, split_type, amount_minor, shares, '
          'percent_bp, space_members(created_at))',
        )
        .isFilter('deleted_at', null)
        .order('spent_on', ascending: false)
        .order('created_at', ascending: false),
    'profiles': db.from('profiles').select('id, name, phone, upi_id'),
    'loans': db
        .from('loans')
        .select(
          'id, lender_id, borrower_id, lender_phone, borrower_phone, '
          'lender_accepted_at, borrower_accepted_at, created_by, closed_at',
        )
        .order('created_at'),
    'loan_summaries': db
        .from('loan_summaries')
        .select(
          'loan_id, principal_minor, outstanding_minor, installment_minor, '
          'installments_total, installments_paid, next_due_on',
        ),
    'loan_repayments': db
        .from('loan_repayments')
        .select('id, loan_id, amount_minor, recorded_by, status')
        .eq('status', 'pending')
        .order('paid_on', ascending: false)
        .order('created_at', ascending: false),
  };
  final rows = await Future.wait(sources.values);
  return Map.fromIterables(sources.keys, rows);
}
