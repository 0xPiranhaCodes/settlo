import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:settlo_core/settlo_core.dart';

/// The shared, busy-guarded mutation state for every repayment decision.
///
/// One controller owns one key for confirmation and one for dispute. A retry
/// therefore cannot apply either final decision twice, and a second tap in the
/// same frame is dropped before Flutter has rebuilt the disabled button.
final class RepaymentDecisionController extends ChangeNotifier {
  /// Decisions for [repaymentId] through [ref].
  new(this.ref, this.repaymentId);

  /// Access to repositories and ledger revision state.
  final WidgetRef ref;

  /// The pending repayment being answered.
  final String repaymentId;

  final String _confirmKey = newIdempotencyKey();
  final String _disputeKey = newIdempotencyKey();

  /// Whether a final decision is in flight or has succeeded.
  bool busy = false;

  /// Plain, customer-safe failure copy from the last attempt.
  String? error;

  /// Clears stale failure copy when the user changes their input.
  void clearError() {
    if (error == null) return;
    error = null;
    notifyListeners();
  }

  /// Confirms the repayment. Returns true only after the ledger was updated.
  Future<bool> confirm() async {
    if (busy) return false;
    busy = true;
    error = null;
    notifyListeners();
    final ledger = ref.read(ledgerRevisionProvider.notifier);
    try {
      await ref
          .read(loansRepositoryProvider)
          .confirmRepayment(repaymentId, idempotencyKey: _confirmKey);
      ledger.bump();
      return true;
    } on LoanRejected catch (e) {
      error = e.message;
    } on Exception {
      error =
          "We couldn't confirm it. Check your connection and try again. "
          "It won't be counted twice.";
    }
    busy = false;
    notifyListeners();
    return false;
  }

  /// Disputes the repayment with a trimmed [reason]. Returns true on success.
  Future<bool> dispute(String reason) async {
    if (busy) return false;
    busy = true;
    error = null;
    notifyListeners();
    final ledger = ref.read(ledgerRevisionProvider.notifier);
    try {
      await ref
          .read(loansRepositoryProvider)
          .disputeRepayment(
            repaymentId,
            reason: reason.trim(),
            idempotencyKey: _disputeKey,
          );
      ledger.bump();
      return true;
    } on LoanRejected catch (e) {
      error = e.message;
    } on Exception {
      error = "We couldn't send it. Check your connection and try again.";
    }
    busy = false;
    notifyListeners();
    return false;
  }
}
