import 'dart:async';

import 'package:settlo_core/settlo_core.dart';

/// An [ExpensesRepository] that records every attempt and throws the
/// queued [failures] first, one per attempt.
class FakeExpensesRepository implements ExpensesRepository {
  /// Every [add] call, with its idempotency key.
  final calls = <({String key, NewExpense expense})>[];

  /// Thrown in order by the next attempts.
  final failures = <Exception>[];

  /// When set, every attempt waits for it, like a slow network.
  Completer<void>? gate;

  @override
  Future<String> add(
    NewExpense expense, {
    required String idempotencyKey,
  }) async {
    calls.add((key: idempotencyKey, expense: expense));
    await gate?.future;
    if (failures.isNotEmpty) throw failures.removeAt(0);
    return 'e-${calls.length}';
  }
}
