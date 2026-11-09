import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:settlo_core/money/paise.dart';
import 'package:settlo_core/supabase/providers.dart';
import 'package:settlo_core/supabase/spaces.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// How an expense is divided between the people in it (docs/api.md).
enum SplitType {
  /// Everyone the same; odd paise to the payer.
  equal,

  /// Amounts typed per person.
  exact,

  /// Percentages, sent as basis points.
  percent,

  /// Whole-number shares.
  shares,
}

/// One person's part of an expense. `percentBp` is set on percent splits
/// and `shares` on shares splits.
typedef ExpenseSplit = ({
  String memberId,
  Paise amount,
  int? percentBp,
  int? shares,
});

/// An expense to record in a space. `payers` maps `space_members.id` to
/// what they paid, in member order; `splits` are in member order too,
/// since order decides who takes odd paise. `spentOn` null means today.
/// A settlement (`isSettlement`) is a payment between members, not
/// spending.
typedef NewExpense = ({
  String spaceId,
  String description,
  String? category,
  Paise amount,
  DateTime? spentOn,
  SplitType splitType,
  bool isSettlement,
  Map<String, Paise> payers,
  List<ExpenseSplit> splits,
});

/// Expenses' writes. Features use this rather than the Supabase client
/// (docs/decisions/2026-11-09-interim-online-repositories.md); tests fake
/// it.
abstract interface class ExpensesRepository {
  /// Records [expense] and returns its id. Retrying with the same
  /// [idempotencyKey] and payload returns the same id and records nothing
  /// new; a changed payload throws [IdempotencyConflict], and one the
  /// server refuses throws [ExpenseRejected].
  Future<String> add(NewExpense expense, {required String idempotencyKey});
}

/// The server refused the expense (`22023`): its sums do not match, or
/// someone in it is no longer an active member of the space.
final class ExpenseRejected implements Exception {
  /// A rejection.
  const new();
}

/// A settle-up between the same payer and payee is already waiting for
/// the payee (`settlement_pending`, #78), so another was not recorded.
final class SettlementPending implements Exception {
  /// A refusal.
  const new();
}

/// [ExpensesRepository] over the `add_expense` RPC (docs/api.md).
final class SupabaseExpensesRepository implements ExpensesRepository {
  /// Writes through [_db].
  const new(this._db);

  final SupabaseClient _db;

  @override
  Future<String> add(
    NewExpense expense, {
    required String idempotencyKey,
  }) async {
    final e = expense;
    try {
      return await _db.rpc<String>(
        'add_expense',
        params: {
          'p': {
            'idempotency_key': idempotencyKey,
            'space_id': e.spaceId,
            'description': e.description,
            'category': ?e.category,
            'amount_minor': e.amount.value,
            // Omitted for today, so a replay after midnight still matches.
            if (e.spentOn case final d?)
              'spent_on':
                  '${d.year}-${d.month.toString().padLeft(2, '0')}-'
                  '${d.day.toString().padLeft(2, '0')}',
            'split_type': e.splitType.name,
            if (e.isSettlement) 'is_settlement': true,
            'payers': [
              for (final MapEntry(:key, :value) in e.payers.entries)
                {'member_id': key, 'amount_minor': value.value},
            ],
            'splits': [
              for (final s in e.splits)
                {
                  'member_id': s.memberId,
                  'amount_minor': s.amount.value,
                  'percent_bp': ?s.percentBp,
                  'shares': ?s.shares,
                },
            ],
          },
        },
      );
    } on PostgrestException catch (error) {
      switch (error.code) {
        case 'PT409':
          throw const IdempotencyConflict();
        case '22023' when error.hint == 'settlement_pending':
          throw const SettlementPending();
        case '22023':
          throw const ExpenseRejected();
      }
      rethrow;
    }
  }
}

/// Expenses through [supabaseClientProvider]; tests override this.
final expensesRepositoryProvider = Provider<ExpensesRepository>(
  (ref) => SupabaseExpensesRepository(ref.watch(supabaseClientProvider)),
);
