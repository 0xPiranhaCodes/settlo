import 'package:settlo_core/settlo_core.dart';
import 'package:settlo_local/src/db.dart';

typedef _Row = Map<String, dynamic>;

/// `YYYY-MM-DD`, as Postgres sends a `date`.
String dateKey(DateTime d) =>
    '${d.year}-${d.month.toString().padLeft(2, '0')}-'
    '${d.day.toString().padLeft(2, '0')}';

/// Applies [queue] in order to the mirrored rows [t] as the server would,
/// so the UI shows every write that is queued or not yet refreshed
/// (ADR 0004). Dropping a mutation is its rollback: nothing optimistic is
/// stored apart from the queue.
///
/// Ids the device made up are `local:<key>` for an expense and
/// `local:<key>:me` / `local:<key>:<phone>` for a new space's members;
/// a new space's id is its key, as `create_space` makes it.
Tables applyQueue(
  Tables t,
  List<Mutation> queue, {
  required String userId,
  required DateTime today,
}) {
  List<_Row> rows(String name) => t[name] ??= [];
  final month = dateKey(DateTime(today.year, today.month));
  final members = rows('space_members');
  final expenses = rows('expenses');
  final pending = rows('pending_settlements');
  final balances = rows('space_member_balances');
  final fairness = rows('space_monthly_fairness');
  final categories = rows('space_monthly_categories');

  _Row balance(Object? member) =>
      balances.where((b) => b['member_id'] == member).firstOrNull ??
      (balances
            ..add({'member_id': member, 'paid_minor': 0, 'balance_minor': 0}))
          .last;

  _Row fair(Object? space, Object? member) {
    final ofSpace = fairness.where((f) => f['space_id'] == space);
    return ofSpace.where((f) => f['member_id'] == member).firstOrNull ??
        (fairness..add({
              'space_id': space,
              'member_id': member,
              'month': month,
              'paid_minor': 0,
              'fair_share_minor': 0,
              'month_total_minor':
                  ofSpace.firstOrNull?['month_total_minor'] ?? 0,
            }))
            .last;
  }

  // What [e] adds to every view, or takes away when [sign] is -1.
  void count(_Row e, int sign) {
    final space = e['space_id'];
    final amount = sign * (e['amount_minor'] as int);
    final payers = (e['expense_payers'] as List).cast<_Row>();
    final splits = (e['expense_splits'] as List).cast<_Row>();
    final status = e['settlement_status'];
    int part(_Row r) => sign * (r['amount_minor'] as int);
    if (e['is_settlement'] != true || status == 'confirmed') {
      for (final p in payers) {
        balance(p['member_id'])
          ..update('paid_minor', (v) => (v as int) + part(p))
          ..update('balance_minor', (v) => (v as int) + part(p));
      }
      for (final s in splits) {
        balance(s['member_id'])
            .update('balance_minor', (v) => (v as int) - part(s));
      }
    }
    if (e['is_settlement'] == true) {
      pending.removeWhere((p) => p['expense_id'] == e['id']);
      if (status == 'pending' && sign > 0) {
        pending.add({
          'expense_id': e['id'],
          'space_id': space,
          'payer_member_id': payers.single['member_id'],
          'payee_member_id': splits.single['member_id'],
          'amount_minor': amount,
        });
      }
      return;
    }
    if (!(e['spent_on'] as String).startsWith(month.substring(0, 8))) return;
    for (final m in members.where((m) => m['space_id'] == space)) {
      fair(space, m['id']);
    }
    for (final f in fairness.where((f) => f['space_id'] == space)) {
      f.update('month_total_minor', (v) => (v as int) + amount);
    }
    for (final p in payers) {
      fair(
        space,
        p['member_id'],
      ).update('paid_minor', (v) => (v as int) + part(p));
    }
    for (final s in splits) {
      fair(
        space,
        s['member_id'],
      ).update('fair_share_minor', (v) => (v as int) + part(s));
    }
    final category =
        categories
                  .where(
                    (c) =>
                        c['space_id'] == space &&
                        c['category'] == e['category'],
                  )
                  .firstOrNull ??
              (categories..add({
                    'space_id': space,
                    'month': month,
                    'category': e['category'],
                    'total_minor': 0,
                    'expense_count': 0,
                  }))
                  .last
          ..update('total_minor', (v) => (v as int) + amount)
          ..update('expense_count', (v) => (v as int) + sign);
    if (category['expense_count'] == 0) categories.remove(category);
  }

  _Row? expense(Object? id) => expenses.where((e) => e['id'] == id).firstOrNull;

  // Newest day first, newest recorded first within a day, as the server
  // orders them.
  void insert(_Row e) {
    final at = expenses.indexWhere(
      (o) => (o['spent_on'] as String).compareTo(e['spent_on'] as String) <= 0,
    );
    expenses.insert(at < 0 ? expenses.length : at, e);
  }

  List<_Row> splitRows(Map<String, dynamic> p, int amount, List<_Row> payers) {
    final splits = (p['splits'] as List).cast<_Row>();
    final type = p['split_type'] as String? ?? 'equal';
    final ids = [for (final s in splits) s['member_id']];
    final payerIds = {for (final r in payers) r['member_id']};
    final equal = type == 'equal'
        ? splitEqual(
            Paise(amount),
            ids,
            payer: ids.where(payerIds.contains).firstOrNull ?? ids.first,
          )
        : const <Object?, Paise>{};
    final joined = {for (final m in members) m['id']: m['created_at']};
    return [
      for (final s in splits)
        {
          'member_id': s['member_id'],
          'split_type': type,
          'amount_minor':
              equal[s['member_id']]?.value ?? s['amount_minor'] as int,
          'percent_bp': s['percent_bp'],
          'shares': s['shares'],
          'space_members': {'created_at': joined[s['member_id']]},
        },
    ];
  }

  for (final m in queue) {
    final params = m.params;
    switch (m.kind) {
      case 'create_space':
        final me = rows('profiles').where((p) => p['id'] == userId);
        final myPhone = me.firstOrNull?['phone'];
        final at = m.createdAt.toUtc().toIso8601String();
        final space = {
          'name': params['p_name'],
          'kind': params['p_kind'],
          'created_by': userId,
          'deleted_at': null,
        };
        final others = [
          for (final o in (params['p_members'] as List).cast<_Row>())
            if (o['phone'] != myPhone) o,
        ];
        for (final (i, o) in [null, ...others].indexed) {
          members.add({
            'id': 'local:${m.key}:${o?['phone'] ?? 'me'}',
            'space_id': m.key,
            'user_id': o == null ? userId : null,
            'name': o?['name'],
            'phone': o?['phone'] ?? myPhone ?? '',
            'role': o == null ? 'owner' : 'member',
            'accepted_at': o == null ? at : null,
            'left_at': null,
            // Keeps member order, which decides who takes odd paise.
            'created_at': '$at#${i.toString().padLeft(3, '0')}',
            'spaces': space,
          });
        }
      case 'add_expense':
        final p = params['p'] as Map<String, dynamic>;
        final amount = p['amount_minor'] as int;
        final payers = [
          for (final r in (p['payers'] as List).cast<_Row>())
            {'member_id': r['member_id'], 'amount_minor': r['amount_minor']},
        ];
        final splits = splitRows(p, amount, payers);
        final settlement = p['is_settlement'] == true;
        final payeeIsMe =
            settlement &&
            members.any(
              (r) =>
                  r['id'] == splits.single['member_id'] &&
                  r['user_id'] == userId,
            );
        final e = {
          'id': 'local:${m.key}',
          'space_id': p['space_id'],
          'description': p['description'],
          'category': p['category'],
          'amount_minor': amount,
          'spent_on': p['spent_on'] ?? dateKey(today),
          'is_settlement': settlement,
          'settlement_status': settlement
              ? (payeeIsMe ? 'confirmed' : 'pending')
              : null,
          'dispute_reason': null,
          'created_by': userId,
          'deleted_at': null,
          'expense_payers': payers,
          'expense_splits': splits,
        };
        insert(e);
        count(e, 1);
      case 'update_expense':
        final p = params['p'] as Map<String, dynamic>;
        final old = expense(p['expense_id']);
        if (old == null) continue;
        count(old, -1);
        final amount = p['amount_minor'] as int;
        final payers = [
          for (final r in (p['payers'] as List).cast<_Row>())
            {'member_id': r['member_id'], 'amount_minor': r['amount_minor']},
        ];
        final updated = {
          ...old,
          'description': p['description'],
          'category': p['category'],
          'amount_minor': amount,
          'spent_on': p['spent_on'] ?? old['spent_on'],
          'expense_payers': payers,
          'expense_splits': splitRows(p, amount, payers),
        };
        expenses.remove(old);
        insert(updated);
        count(updated, 1);
      case 'delete_expense':
        final old = expense(params['p_expense_id']);
        if (old == null) continue;
        count(old, -1);
        expenses.remove(old);
      case 'confirm_settlement' || 'dispute_settlement':
        final old = expense(params['p_expense_id']);
        if (old == null || old['settlement_status'] != 'pending') continue;
        count(old, -1);
        final confirmed = m.kind == 'confirm_settlement';
        old['settlement_status'] = confirmed ? 'confirmed' : 'disputed';
        old['dispute_reason'] = params['p_reason'];
        count(old, 1);
    }
  }
  return t;
}
