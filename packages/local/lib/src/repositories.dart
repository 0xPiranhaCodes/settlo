import 'package:settlo_core/settlo_core.dart';
import 'package:settlo_local/src/sync.dart';

/// [HomeRepository] over the mirror. Claims stay online: their RPCs take
/// no idempotency key, so they cannot be queued safely (follow-up on #53).
final class DriftHomeRepository implements HomeRepository {
  /// Reads through [_sync]; claims go through [_online].
  const new(this._sync, this._online, {this.now = DateTime.now});

  final SyncEngine _sync;
  final HomeRepository _online;

  /// The clock.
  final DateTime Function() now;

  @override
  Future<HomeData> load() async {
    final today = now();
    return homeFromRows(
      await _sync.snapshot(today),
      userId: _sync.owner,
      month: DateTime(today.year, today.month),
    );
  }

  @override
  Future<void> acceptClaim(Claim claim) async {
    await _online.acceptClaim(claim);
    await _sync.sync();
  }

  @override
  Future<void> rejectClaim(Claim claim) async {
    await _online.rejectClaim(claim);
    await _sync.sync();
  }
}

/// [SpacesRepository] over the mirror; a new space is queued.
final class DriftSpacesRepository implements SpacesRepository {
  /// Reads and writes through [_sync].
  const new(this._sync, {this.now = DateTime.now});

  final SyncEngine _sync;

  /// The clock.
  final DateTime Function() now;

  @override
  Future<List<SpaceSummary>> load() async {
    final today = now();
    return spacesFromRows(
      await _sync.snapshot(today),
      userId: _sync.owner,
      month: DateTime(today.year, today.month),
    );
  }

  @override
  Future<String> create({
    required String name,
    required SpaceKind kind,
    required List<NewSpaceMember> members,
    required String idempotencyKey,
  }) async {
    await _sync.submit(
      'create_space',
      createSpaceParams(
        name: name,
        kind: kind,
        members: members,
        idempotencyKey: idempotencyKey,
      ),
      idempotencyKey,
    );
    // create_space makes the key the space's id.
    return idempotencyKey;
  }
}

/// [ExpensesRepository] that queues every expense.
final class DriftExpensesRepository implements ExpensesRepository {
  /// Writes through [_sync].
  const new(this._sync);

  final SyncEngine _sync;

  @override
  Future<String> add(NewExpense expense, {required String idempotencyKey}) =>
      _sync.submit(
        'add_expense',
        addExpenseParams(expense, idempotencyKey: idempotencyKey),
        idempotencyKey,
      );
}

/// [SpaceLedgerRepository] over the mirror; every write is queued.
final class DriftSpaceLedgerRepository implements SpaceLedgerRepository {
  /// Reads and writes through [_sync].
  const new(this._sync, {this.now = DateTime.now});

  final SyncEngine _sync;

  /// The clock.
  final DateTime Function() now;

  @override
  Future<SpaceLedger> load(String spaceId) async {
    final today = now();
    final t = await _sync.snapshot(today);
    List<Map<String, dynamic>> inSpace(String source) => [
      ...?t[source]?.where((r) => r['space_id'] == spaceId),
    ];
    return ledgerFromRows(
      {
        'expenses': inSpace('expenses'),
        'space_monthly_fairness': inSpace('space_monthly_fairness'),
        'space_monthly_categories': inSpace('space_monthly_categories')
          ..sort(
            (a, b) =>
                (b['total_minor'] as int).compareTo(a['total_minor'] as int),
          ),
      },
      userId: _sync.owner,
      today: DateTime(today.year, today.month, today.day),
    );
  }

  @override
  Future<void> updateExpense(
    ExpenseUpdate update, {
    required String idempotencyKey,
  }) => _sync.submit(
    'update_expense',
    updateExpenseParams(update, idempotencyKey: idempotencyKey),
    idempotencyKey,
  );

  @override
  Future<void> deleteExpense(
    String expenseId, {
    required String idempotencyKey,
  }) => _sync.submit(
    'delete_expense',
    deleteExpenseParams(expenseId, idempotencyKey: idempotencyKey),
    idempotencyKey,
  );

  @override
  Future<void> confirmSettlement(
    String expenseId, {
    required Paise amount,
    required String payerMemberId,
    required String idempotencyKey,
  }) => _sync.submit(
    'confirm_settlement',
    confirmSettlementParams(
      expenseId,
      amount: amount,
      payerMemberId: payerMemberId,
      idempotencyKey: idempotencyKey,
    ),
    idempotencyKey,
  );

  @override
  Future<void> disputeSettlement(
    String expenseId,
    String reason, {
    required String idempotencyKey,
  }) => _sync.submit(
    'dispute_settlement',
    disputeSettlementParams(expenseId, reason, idempotencyKey: idempotencyKey),
    idempotencyKey,
  );
}
