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
/// a new space's, loan's or repayment's id is its key, as their RPCs make
/// it.
///
/// The activity feed is the server's history and is left as mirrored.
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
  late final loans = rows('loans');
  late final summaries = rows('loan_summaries');
  late final repayments = rows('loan_repayments');
  // Loans are dated in India (docs/api.md).
  DateTime india(DateTime t) =>
      t.toUtc().add(const Duration(hours: 5, minutes: 30));

  // Sets what `loan_summaries` derives from [s]'s confirmed repayments.
  void schedule(_Row s) {
    final principal = s['principal_minor'] as int;
    final repaid = s['repaid_minor'] as int;
    final closed = repaid == principal;
    s['outstanding_minor'] = principal - repaid;
    final installment = s['installment_minor'] as int?;
    if (installment == null) return;
    final n = s['installments_total'] as int;
    final start = DateTime.parse(s['start_on'] as String);
    final day = s['due_day'] as int;
    final ist = india(today);
    final monthsIn = (ist.year - start.year) * 12 + ist.month - start.month;
    final due = (monthsIn - 1 + (day < ist.day ? 1 : 0)).clamp(0, n);
    s['installments_paid'] = closed ? n : repaid ~/ installment;
    s['next_due_on'] = closed || due >= n
        ? null
        : dateKey(DateTime(start.year, start.month + due + 1, day));
    final expected = installment * due;
    s['on_track'] = closed
        ? null
        : repaid >= (expected < principal ? expected : principal);
  }

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
        t['needs_you']?.removeWhere((n) => n['id'] == params['p_expense_id']);
        final old = expense(params['p_expense_id']);
        if (old == null) continue;
        count(old, -1);
        expenses.remove(old);
      case 'confirm_settlement' || 'dispute_settlement':
        t['needs_you']?.removeWhere((n) => n['id'] == params['p_expense_id']);
        final old = expense(params['p_expense_id']);
        if (old == null || old['settlement_status'] != 'pending') continue;
        count(old, -1);
        final confirmed = m.kind == 'confirm_settlement';
        old['settlement_status'] = confirmed ? 'confirmed' : 'disputed';
        old['dispute_reason'] = params['p_reason'];
        count(old, 1);
      case 'create_loan':
        final p = params['p'] as Map<String, dynamic>;
        final (mine, theirs) = p['direction'] == 'lent'
            ? ('lender', 'borrower')
            : ('borrower', 'lender');
        final me = rows('profiles').where((r) => r['id'] == userId);
        final at = m.createdAt.toUtc().toIso8601String();
        final principal = p['principal_minor'] as int;
        final installment = p['installment_minor'] as int?;
        final start = DateTime.parse(p['start_on'] as String);
        final n = installment == null
            ? null
            : (principal + installment - 1) ~/ installment;
        loans.add({
          'id': m.key,
          '${mine}_id': userId,
          '${theirs}_id': null,
          '${mine}_phone': me.firstOrNull?['phone'] ?? '',
          '${theirs}_phone': p['counterparty_phone'],
          '${mine}_accepted_at': at,
          '${theirs}_accepted_at': null,
          'created_by': userId,
          'closed_at': null,
        });
        final summary = <String, dynamic>{
          'loan_id': m.key,
          'principal_minor': principal,
          'repaid_minor': 0,
          'installment_minor': installment,
          'due_day': p['due_day'],
          'start_on': p['start_on'],
          'closed_at': null,
          'installments_total': n,
          'installments_paid': null,
          'next_due_on': null,
          'ends_on': n == null
              ? null
              : dateKey(
                  DateTime(start.year, start.month + n, p['due_day'] as int),
                ),
          'on_track': null,
        };
        schedule(summary);
        summaries.add(summary);
      case 'record_repayment':
        final p = params['p'] as Map<String, dynamic>;
        final r = {
          'id': m.key,
          'loan_id': p['loan_id'],
          'amount_minor': p['amount_minor'],
          'paid_on': p['paid_on'] ?? dateKey(india(m.createdAt)),
          'method': p['method'],
          'reference': p['reference'],
          'recorded_by': userId,
          'status': 'pending',
          'dispute_reason': null,
        };
        // Newest paid first, as the server orders them.
        final at = repayments.indexWhere(
          (o) =>
              (o['paid_on'] as String).compareTo(r['paid_on'] as String) <= 0,
        );
        repayments.insert(at < 0 ? repayments.length : at, r);
      case 'confirm_repayment' || 'dispute_repayment':
        final id = params['p_repayment_id'];
        t['needs_you']?.removeWhere((n) => n['id'] == id);
        final r = repayments.where((r) => r['id'] == id).firstOrNull;
        if (r == null || r['status'] != 'pending') continue;
        if (m.kind == 'dispute_repayment') {
          r['status'] = 'disputed';
          r['dispute_reason'] = (params['p_reason'] as String).trim();
          continue;
        }
        r['status'] = 'confirmed';
        final s = summaries
            .where((s) => s['loan_id'] == r['loan_id'])
            .firstOrNull;
        if (s == null) continue;
        s['repaid_minor'] =
            (s['repaid_minor'] as int) + (r['amount_minor'] as int);
        schedule(s);
        // The last repayment closes the loan (`close_repaid_loan`).
        if (s['outstanding_minor'] == 0) {
          final at = m.createdAt.toUtc().toIso8601String();
          s['closed_at'] = at;
          loans
                  .where((l) => l['id'] == r['loan_id'])
                  .firstOrNull?['closed_at'] =
              at;
        }
      case 'accept_claim' || 'reject_claim':
        final accept = m.kind == 'accept_claim';
        final at = m.createdAt.toUtc().toIso8601String();
        if (params['p_kind'] == 'space_member') {
          final row = members
              .where((r) => r['id'] == params['p_id'])
              .firstOrNull;
          if (row == null || row['accepted_at'] != null) continue;
          if (accept) {
            row['accepted_at'] = at;
          } else {
            // 'This isn't me' unlinks the number and leaves the space.
            row['user_id'] = null;
            row['left_at'] = at;
          }
        } else {
          final l = loans.where((l) => l['id'] == params['p_id']).firstOrNull;
          if (l == null) continue;
          final side = l['lender_id'] == userId ? 'lender' : 'borrower';
          if (accept) {
            l['${side}_accepted_at'] ??= at;
          } else if (l['${side}_accepted_at'] == null) {
            l['${side}_id'] = null;
          }
        }
    }
  }
  return t;
}
