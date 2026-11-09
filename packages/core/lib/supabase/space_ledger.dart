import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:settlo_core/money/paise.dart';
import 'package:settlo_core/supabase/expenses.dart';
import 'package:settlo_core/supabase/providers.dart';
import 'package:settlo_core/supabase/spaces.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Who paid part of an expense.
typedef ExpensePayer = ({String memberId, Paise amount});

/// Where a settle-up stands (#78). Only a confirmed one counts toward
/// balances; the payee confirms or disputes a pending one, once.
enum SettlementStatus {
  /// Recorded by someone other than the payee; waiting for the payee.
  pending,

  /// Confirmed by the payee, or recorded by them. Final.
  confirmed,

  /// The payee says it never arrived. Final; it never counts.
  disputed,
}

/// An expense in a space that has not been deleted.
@immutable
final class SpaceExpense {
  /// An expense row with its payers and splits.
  const new({
    required this.id,
    required this.description,
    required this.amount,
    required this.spentOn,
    required this.payers,
    required this.splits,
    this.category,
    this.splitType = 'equal',
    this.isSettlement = false,
    this.settlementStatus,
    this.disputeReason,
    this.createdByYou = false,
  });

  /// `expenses.id`.
  final String id;

  /// What it was for.
  final String description;

  /// Its category, if any.
  final String? category;

  /// The whole amount.
  final Paise amount;

  /// The day it was spent.
  final DateTime spentOn;

  /// `equal`, `exact`, `percent` or `shares`.
  final String splitType;

  /// Whether it records a settle-up rather than spending.
  final bool isSettlement;

  /// Where a settle-up stands; null for spending.
  final SettlementStatus? settlementStatus;

  /// Why the payee disputed it.
  final String? disputeReason;

  /// Whether the signed-in user recorded it.
  final bool createdByYou;

  /// Who paid, summing to [amount].
  final List<ExpensePayer> payers;

  /// Who it is split between, in the space's member order, summing to
  /// [amount].
  final List<ExpenseSplit> splits;
}

/// What one member paid this month against their fair share, the sum of
/// their agreed splits (docs/decisions/2026-11-09-fair-share.md).
typedef MemberFairness = ({Paise paid, Paise fairShare});

/// A month's spending in one category; a null category is its own group.
typedef CategoryTotal = ({String? category, Paise total, int count});

/// A space's expenses and this month's fairness and categories.
@immutable
final class SpaceLedger {
  /// A loaded ledger.
  const new({
    required this.today,
    this.expenses = const [],
    this.fairness = const {},
    this.categories = const [],
  });

  /// The day it was loaded, which picks the month.
  final DateTime today;

  /// The first day of the month [fairness] and [categories] cover.
  DateTime get month => DateTime(today.year, today.month);

  /// Every live expense, newest day first.
  final List<SpaceExpense> expenses;

  /// This month's fairness by `space_members.id`.
  final Map<String, MemberFairness> fairness;

  /// This month's spending by category, largest first.
  final List<CategoryTotal> categories;
}

/// An edit to a [SpaceExpense]: `update_expense` replaces every field,
/// so this carries the payers, splits and settlement flag to keep as
/// well. An omitted `is_settlement` would reset a settle-up to spending.
typedef ExpenseUpdate = ({
  String id,
  String description,
  String? category,
  Paise amount,
  DateTime spentOn,
  bool isSettlement,
  String splitType,
  List<ExpensePayer> payers,
  List<ExpenseSplit> splits,
});

/// A space's expenses, fairness and categories, and edits to expenses.
/// Features use this rather than the Supabase client
/// (docs/decisions/2026-11-09-interim-online-repositories.md); tests fake
/// it.
abstract interface class SpaceLedgerRepository {
  /// Space [spaceId]'s live expenses and this month's views.
  Future<SpaceLedger> load(String spaceId);

  /// Saves [update]. Allowed for its creator or a space owner. A retry
  /// must pass the same [idempotencyKey]; a changed payload throws
  /// [IdempotencyConflict].
  Future<void> updateExpense(
    ExpenseUpdate update, {
    required String idempotencyKey,
  });

  /// Soft-deletes expense [expenseId], which then stops counting
  /// everywhere. Allowed for its creator or a space owner; a retry must
  /// pass the same [idempotencyKey].
  Future<void> deleteExpense(
    String expenseId, {
    required String idempotencyKey,
  });

  /// The payee confirms pending settle-up [expenseId]; it counts from
  /// then on. A retry must pass the same [idempotencyKey].
  Future<void> confirmSettlement(
    String expenseId, {
    required String idempotencyKey,
  });

  /// The payee says pending settle-up [expenseId] never arrived, with
  /// [reason]; it never counts. A retry must pass the same
  /// [idempotencyKey] and [reason].
  Future<void> disputeSettlement(
    String expenseId,
    String reason, {
    required String idempotencyKey,
  });
}

typedef _Row = Map<String, dynamic>;

/// When a split's member was added to the space.
String _joined(_Row split) =>
    '${(split['space_members'] as _Row?)?['created_at']}';

String _date(DateTime d) =>
    '${d.year}-${d.month.toString().padLeft(2, '0')}-'
    '${d.day.toString().padLeft(2, '0')}';

/// [SpaceLedgerRepository] over PostgREST: `expenses` with their payers
/// and splits, the monthly views, and the `update_expense`,
/// `delete_expense`, `confirm_settlement` and `dispute_settlement` RPCs
/// (docs/api.md).
final class SupabaseSpaceLedgerRepository implements SpaceLedgerRepository {
  /// Reads as [userId] through [_db]; [now] picks the month.
  const new(this._db, {required this.userId, this.now = DateTime.now});

  final SupabaseClient _db;

  /// The signed-in user's id.
  final String userId;

  /// The clock.
  final DateTime Function() now;

  @override
  Future<SpaceLedger> load(String spaceId) async {
    final today = now();
    final month = DateTime(today.year, today.month);
    final [expenses, fairness, categories] = await Future.wait<List<_Row>>([
      _db
          .from('expenses')
          .select(
            'id, description, category, amount_minor, spent_on, '
            'is_settlement, settlement_status, dispute_reason, created_by, '
            'deleted_at, '
            'expense_payers(member_id, amount_minor), '
            'expense_splits(member_id, split_type, amount_minor, shares, '
            'percent_bp, space_members(created_at))',
          )
          .eq('space_id', spaceId)
          .isFilter('deleted_at', null)
          .order('spent_on', ascending: false)
          .order('created_at', ascending: false),
      _db
          .from('space_monthly_fairness')
          .select('member_id, paid_minor, fair_share_minor')
          .eq('space_id', spaceId)
          .eq('month', _date(month)),
      _db
          .from('space_monthly_categories')
          .select('category, total_minor, expense_count')
          .eq('space_id', spaceId)
          .eq('month', _date(month))
          .order('total_minor', ascending: false),
    ]);
    Paise money(_Row row) => Paise(row['amount_minor'] as int);
    return SpaceLedger(
      today: DateTime(today.year, today.month, today.day),
      expenses: [
        for (final e in expenses)
          if (e['deleted_at'] == null)
            SpaceExpense(
              id: e['id'] as String,
              description: e['description'] as String,
              category: e['category'] as String?,
              amount: money(e),
              spentOn: DateTime.parse(e['spent_on'] as String),
              isSettlement: e['is_settlement'] as bool? ?? false,
              settlementStatus: switch (e['settlement_status']) {
                final String s => SettlementStatus.values.byName(s),
                _ => null,
              },
              disputeReason: e['dispute_reason'] as String?,
              createdByYou: e['created_by'] == userId,
              splitType:
                  ((e['expense_splits'] as List).firstOrNull
                          as _Row?)?['split_type']
                      as String? ??
                  'equal',
              payers: [
                for (final p in (e['expense_payers'] as List).cast<_Row>())
                  (memberId: p['member_id'] as String, amount: money(p)),
              ],
              // Splits have no stored order, but an edit's remainder and
              // ties go by it, so send them back in member order, as
              // they were first sent.
              splits: [
                for (final s
                    in (e['expense_splits'] as List).cast<_Row>().toList()
                      ..sort((a, b) => _joined(a).compareTo(_joined(b))))
                  (
                    memberId: s['member_id'] as String,
                    amount: money(s),
                    percentBp: s['percent_bp'] as int?,
                    shares: s['shares'] as int?,
                  ),
              ],
            ),
      ],
      fairness: {
        for (final f in fairness)
          f['member_id'] as String: (
            paid: Paise(f['paid_minor'] as int),
            fairShare: Paise(f['fair_share_minor'] as int),
          ),
      },
      categories: [
        for (final c in categories)
          (
            category: c['category'] as String?,
            total: Paise(c['total_minor'] as int),
            count: c['expense_count'] as int,
          ),
      ],
    );
  }

  @override
  Future<void> updateExpense(
    ExpenseUpdate update, {
    required String idempotencyKey,
  }) => _call('update_expense', {
    'p': {
      'expense_id': update.id,
      'idempotency_key': idempotencyKey,
      'description': update.description,
      'category': update.category,
      'amount_minor': update.amount.value,
      'spent_on': _date(update.spentOn),
      'is_settlement': update.isSettlement,
      'split_type': update.splitType,
      'payers': [
        for (final p in update.payers)
          {'member_id': p.memberId, 'amount_minor': p.amount.value},
      ],
      'splits': [
        for (final s in update.splits)
          {
            'member_id': s.memberId,
            // The server recomputes equal splits, so a new amount needs
            // no amounts here.
            if (update.splitType != 'equal') 'amount_minor': s.amount.value,
            'percent_bp': ?s.percentBp,
            'shares': ?s.shares,
          },
      ],
    },
  });

  @override
  Future<void> deleteExpense(
    String expenseId, {
    required String idempotencyKey,
  }) => _call('delete_expense', {
    'p_expense_id': expenseId,
    'p_idempotency_key': idempotencyKey,
  });

  @override
  Future<void> confirmSettlement(
    String expenseId, {
    required String idempotencyKey,
  }) => _call('confirm_settlement', {
    'p_expense_id': expenseId,
    'p_idempotency_key': idempotencyKey,
  });

  @override
  Future<void> disputeSettlement(
    String expenseId,
    String reason, {
    required String idempotencyKey,
  }) => _call('dispute_settlement', {
    'p_expense_id': expenseId,
    'p_reason': reason,
    'p_idempotency_key': idempotencyKey,
  });

  Future<void> _call(String fn, Map<String, Object?> params) async {
    try {
      await _db.rpc<Object?>(fn, params: params);
    } on PostgrestException catch (e) {
      if (e.code == 'PT409') throw const IdempotencyConflict();
      rethrow;
    }
  }
}

/// The ledger for the signed-in user through [supabaseClientProvider];
/// tests override this. Rebuilt only when the user changes.
final spaceLedgerRepositoryProvider = Provider<SpaceLedgerRepository>((ref) {
  final userId = ref.watch(sessionProvider.select((s) => s?.user.id));
  if (userId == null) throw StateError('A space needs a signed-in user');
  return SupabaseSpaceLedgerRepository(
    ref.watch(supabaseClientProvider),
    userId: userId,
  );
});
