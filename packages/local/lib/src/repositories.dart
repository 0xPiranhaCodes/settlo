import 'package:settlo_core/settlo_core.dart';
import 'package:settlo_local/src/sync.dart';

/// [HomeRepository] over the mirror; a claim decision is queued.
final class DriftHomeRepository implements HomeRepository {
  /// Reads and writes through [_sync].
  const new(this._sync, {this.now = DateTime.now});

  final SyncEngine _sync;

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
  Future<void> acceptClaim(Claim claim, {required String idempotencyKey}) =>
      _sync.submit(
        'accept_claim',
        claimParams(claim, idempotencyKey: idempotencyKey),
        idempotencyKey,
      );

  @override
  Future<void> rejectClaim(Claim claim, {required String idempotencyKey}) =>
      _sync.submit(
        'reject_claim',
        claimParams(claim, idempotencyKey: idempotencyKey),
        idempotencyKey,
      );
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

/// [LoansRepository] over the mirror; every write is queued.
final class DriftLoansRepository implements LoansRepository {
  /// Reads and writes through [_sync].
  const new(this._sync, {this.now = DateTime.now});

  final SyncEngine _sync;

  /// The clock. India's date decides what is due (UTC+5:30).
  final DateTime Function() now;

  @override
  Future<LoansData> load() async {
    final today = now();
    final ist = today.toUtc().add(const Duration(hours: 5, minutes: 30));
    return loansFromRows(
      await _sync.snapshot(today),
      userId: _sync.owner,
      today: DateTime(ist.year, ist.month, ist.day),
    );
  }

  @override
  Future<String> createLoan(
    NewLoan loan, {
    required String idempotencyKey,
  }) async {
    await _sync.submit(
      'create_loan',
      createLoanParams(loan, idempotencyKey: idempotencyKey),
      idempotencyKey,
    );
    // create_loan makes the key the loan's id.
    return idempotencyKey;
  }

  @override
  Future<String> recordRepayment(
    NewRepayment repayment, {
    required String idempotencyKey,
  }) async {
    await _sync.submit(
      'record_repayment',
      recordRepaymentParams(repayment, idempotencyKey: idempotencyKey),
      idempotencyKey,
    );
    // record_repayment makes the key the repayment's id.
    return idempotencyKey;
  }

  @override
  Future<void> confirmRepayment(
    String repaymentId, {
    required String idempotencyKey,
  }) => _sync.submit(
    'confirm_repayment',
    confirmRepaymentParams(repaymentId, idempotencyKey: idempotencyKey),
    idempotencyKey,
  );

  @override
  Future<void> disputeRepayment(
    String repaymentId, {
    required String reason,
    required String idempotencyKey,
  }) => _sync.submit(
    'dispute_repayment',
    disputeRepaymentParams(
      repaymentId,
      reason: reason,
      idempotencyKey: idempotencyKey,
    ),
    idempotencyKey,
  );
}

/// [ActivityRepository] over the mirror, which keeps the newest
/// [mirroredActivity] entries; pages older than those come from [_online],
/// so they need a connection.
final class DriftActivityRepository implements ActivityRepository {
  /// Reads through [_sync]; history past the mirror through [_online].
  const new(this._sync, this._online, {this.now = DateTime.now});

  final SyncEngine _sync;
  final ActivityRepository _online;

  /// The clock.
  final DateTime Function() now;

  @override
  Future<List<ActivityEntry>> feed({
    required int limit,
    ActivityEntry? before,
  }) async {
    final rows = (await _sync.snapshot(now()))['activity_feed'] ?? const [];
    final page = [
      for (final e in activityFromRows(rows))
        if (before == null ||
            e.at.isBefore(before.at) ||
            (e.at.isAtSameMomentAs(before.at) && e.id < before.id))
          e,
    ];
    if (page.length >= limit || rows.length < mirroredActivity) {
      return page.take(limit).toList();
    }
    try {
      return await _online.feed(limit: limit, before: before);
    } on Exception {
      // Offline: what the mirror has left; the rest loads once back.
      return page;
    }
  }

  @override
  Future<List<PendingAnswer>> needsYou() async =>
      needsYouFromRows((await _sync.snapshot(now()))['needs_you'] ?? const []);
}
