import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:settlo_core/money/paise.dart';
import 'package:settlo_core/supabase/providers.dart';
import 'package:settlo_core/supabase/spaces.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Where a repayment stands. Only [confirmed] ones count.
enum RepaymentStatus {
  /// Recorded by one party, waiting for the other.
  pending,

  /// The other party said it arrived. Final.
  confirmed,

  /// The other party said it did not. Final; it never counts.
  disputed,
}

/// How a repayment was paid (`repayment_method`).
enum RepaymentMethod {
  /// A UPI app.
  upi('UPI'),

  /// Cash.
  cash('Cash'),

  /// A bank transfer.
  bank('Bank'),

  /// Anything else.
  other('Other');

  new(this.label);

  /// How the history names it.
  final String label;
}

/// One repayment on a [Loan], as both parties see it.
@immutable
final class LoanRepayment {
  /// A `loan_repayments` row.
  const new({
    required this.id,
    required this.amount,
    required this.paidOn,
    required this.status,
    required this.recordedByYou,
    this.method,
    this.reference,
    this.disputeReason,
  });

  /// `loan_repayments.id`.
  final String id;

  /// What was repaid; all principal while loans are interest free.
  final Paise amount;

  /// The day it was paid.
  final DateTime paidOn;

  /// How it was paid, if recorded.
  final RepaymentMethod? method;

  /// A UPI transaction id or similar, if recorded.
  final String? reference;

  /// Pending, confirmed or disputed.
  final RepaymentStatus status;

  /// Whether your side recorded it. Only the other side may confirm or
  /// dispute a pending repayment.
  final bool recordedByYou;

  /// Why the other party disputed it.
  final String? disputeReason;

  /// Whether you are the one to confirm or dispute it.
  bool get awaitsYou => status == RepaymentStatus.pending && !recordedByYou;
}

/// A loan the signed-in user has accepted, with its schedule and
/// repayments (`loan_summaries` and `loan_repayments`, docs/api.md).
@immutable
final class Loan {
  /// A loan; [repaid] counts confirmed repayments only.
  const new({
    required this.id,
    required this.counterparty,
    required this.youLent,
    required this.principal,
    required this.repaid,
    required this.startOn,
    this.installment,
    this.dueDay,
    this.installmentsPaid,
    this.installmentsTotal,
    this.nextDueOn,
    this.endsOn,
    this.onTrack,
    this.closed = false,
    this.repayments = const [],
  });

  /// `loans.id`.
  final String id;

  /// The other party's name, or their number when it is not visible.
  final String counterparty;

  /// Whether you are the lender.
  final bool youLent;

  /// What was lent.
  final Paise principal;

  /// Principal of confirmed repayments. Pending ones never count.
  final Paise repaid;

  /// The day the loan started.
  final DateTime startOn;

  /// The monthly instalment; null for a flexible loan.
  final Paise? installment;

  /// The day of the month instalments fall due (1–28); null when flexible.
  final int? dueDay;

  /// Instalments repaid; null for a flexible loan.
  final int? installmentsPaid;

  /// Instalments in the schedule; null for a flexible loan.
  final int? installmentsTotal;

  /// The next instalment's date; null when none is left or flexible.
  final DateTime? nextDueOn;

  /// The last instalment's date; null for a flexible loan.
  final DateTime? endsOn;

  /// Whether confirmed repayments keep up with the schedule; null when
  /// flexible or closed.
  final bool? onTrack;

  /// Whether confirmed repayments reached the principal.
  final bool closed;

  /// Every repayment, newest first, disputed ones included.
  final List<LoanRepayment> repayments;

  /// What is still owed: [principal] minus [repaid].
  Paise get outstanding => principal - repaid;

  /// What would remain after [repayment].
  ///
  /// [repaid] already includes every confirmed repayment, so only a pending
  /// repayment is added for this projection. Disputed repayments never count,
  /// and an invalid overpayment is shown as zero rather than negative money.
  Paise outstandingAfter(LoanRepayment repayment) {
    final remaining = principal - _confirmedAfter(repayment);
    return remaining.value < 0 ? Paise.zero : remaining;
  }

  /// Which scheduled instalment [repayment] represents.
  ///
  /// A pending repayment projects the count after confirmation from the
  /// confirmed principal, rounded down to complete instalments and capped at
  /// the schedule total. Decided receipts keep the server's current count.
  /// Flexible loans have no instalment count.
  int? installmentsAfter(LoanRepayment repayment) {
    final amount = installment;
    final total = installmentsTotal;
    if (amount == null || total == null) return null;
    if (repayment.status != RepaymentStatus.pending || amount.value <= 0) {
      return installmentsPaid;
    }
    final projected = _confirmedAfter(repayment).value ~/ amount.value;
    return projected > total ? total : projected;
  }

  Paise _confirmedAfter(LoanRepayment repayment) =>
      repayment.status == RepaymentStatus.pending
      ? repaid + repayment.amount
      : repaid;

  /// The share repaid, 0 to 1, from confirmed repayments only.
  double get progress =>
      principal.value == 0 ? 0 : (repaid.value / principal.value).clamp(0, 1);

  /// Whether a pending repayment waits for your answer.
  bool get awaitsYou => repayments.any((r) => r.awaitsYou);
}

/// Your loans and the day they were loaded, which dates "in 26 days".
@immutable
final class LoansData {
  /// Loaded loans.
  const new({required this.today, this.loans = const [], this.yourName});

  /// India's date when loaded, at midnight.
  final DateTime today;

  /// Your profile name (`profiles.name`), if set.
  final String? yourName;

  /// Open loans first, then closed ones, oldest first within each.
  final List<Loan> loans;
}

/// A loan to create: monthly with `installment` and `dueDay` (1–28),
/// flexible with neither. Loans are interest free in v1.
typedef NewLoan = ({
  bool youLent,
  String counterpartyPhone,
  Paise principal,
  Paise? installment,
  int? dueDay,
  DateTime startOn,
});

/// A repayment to record; the loan's other party then confirms it.
typedef NewRepayment = ({
  String loanId,
  Paise amount,
  RepaymentMethod? method,
  DateTime? paidOn,
  String? reference,
});

/// Why the server refused a loan write. Each maps to plain copy in
/// [LoanRejected.message]; raw Postgres errors never reach the screen.
enum LoanRejection {
  /// More than is outstanding (`overpayment`).
  overpayment,

  /// Recording on a fully repaid loan (`loan_closed`).
  closed,

  /// Already confirmed or disputed, perhaps from another device
  /// (`not_pending`).
  notPending,

  /// Answering a repayment your own side recorded (`own_record`).
  ownRecord,

  /// You are not an accepted party to the loan (`42501`).
  notAllowed,

  /// Anything else the server refused (`22023`), such as a bad reason or
  /// a loan with your own number.
  invalid,
}

/// The server refused a loan write for [reason].
final class LoanRejected implements Exception {
  /// A refusal.
  const new(this.reason);

  /// Why.
  final LoanRejection reason;

  /// What to tell the user.
  String get message => switch (reason) {
    LoanRejection.overpayment =>
      "That's more than is left on the loan. Check the amount.",
    LoanRejection.closed =>
      'This loan is fully repaid. Nothing more to record.',
    LoanRejection.notPending =>
      'This repayment was already answered. Pull down to see it.',
    LoanRejection.ownRecord =>
      'Your side recorded this one, so the other person confirms it.',
    LoanRejection.notAllowed => "You can't change this loan.",
    LoanRejection.invalid => "That didn't go through. Check it and try again.",
  };

  @override
  String toString() => 'LoanRejected(${reason.name})';
}

/// Loans' reads and writes. Features use this rather than
/// the Supabase client
/// (docs/decisions/2026-11-09-interim-online-repositories.md); tests fake
/// it.
///
/// Every write takes an idempotency key made once per user action (one
/// per sheet or per button press) and reused on every retry of it, so a
/// dropped connection never records anything twice. A key reused with a
/// different payload throws [IdempotencyConflict]; a refusal throws
/// [LoanRejected].
abstract interface class LoansRepository {
  /// The loans you have accepted, with their repayments.
  Future<LoansData> load();

  /// Creates [loan] between you and its counterparty's number and returns
  /// its id (the key). Their side is a pending claim until that number
  /// verifies and accepts; nothing about them is revealed before then.
  Future<String> createLoan(NewLoan loan, {required String idempotencyKey});

  /// Records [repayment] as pending and returns its id (the key).
  /// The repayment's paid-on date is null for today; its reference is a
  /// trimmed UPI, bank or cash reference when the recorder supplied one.
  Future<String> recordRepayment(
    NewRepayment repayment, {
    required String idempotencyKey,
  });

  /// Confirms pending repayment [repaymentId], which the other side
  /// recorded. Final; it then counts, and may close the loan.
  Future<void> confirmRepayment(
    String repaymentId, {
    required String idempotencyKey,
  });

  /// Disputes pending repayment [repaymentId] with [reason] (1–500
  /// characters once trimmed). Final; it never counts.
  Future<void> disputeRepayment(
    String repaymentId, {
    required String reason,
    required String idempotencyKey,
  });
}

typedef _Row = Map<String, dynamic>;

DateTime? _day(Object? d) => d is String ? DateTime.parse(d) : null;

/// [LoansRepository] over PostgREST: `loans`, `loan_summaries`,
/// `loan_repayments` and `profiles` joined on device, and the
/// `create_loan`, `record_repayment`, `confirm_repayment` and
/// `dispute_repayment` RPCs
/// (docs/api.md).
final class SupabaseLoansRepository implements LoansRepository {
  /// Reads as [userId] through [_db]; [now] dates the load.
  const new(this._db, {required this.userId, this.now = DateTime.now});

  final SupabaseClient _db;

  /// The signed-in user's id.
  final String userId;

  /// The clock. India's date decides what is due, so this is read in
  /// IST (UTC+5:30, no daylight saving).
  final DateTime Function() now;

  @override
  Future<LoansData> load() async {
    final ist = now().toUtc().add(const Duration(hours: 5, minutes: 30));
    final [
      loans,
      summaries,
      repayments,
      profiles,
    ] = await Future.wait<List<_Row>>([
      _db
          .from('loans')
          .select(
            'id, lender_id, borrower_id, lender_phone, borrower_phone, '
            'lender_accepted_at, borrower_accepted_at',
          )
          .order('created_at'),
      _db
          .from('loan_summaries')
          .select(
            'loan_id, principal_minor, repaid_minor, installment_minor, '
            'due_day, start_on, closed_at, installments_total, '
            'installments_paid, next_due_on, ends_on, on_track',
          ),
      _db
          .from('loan_repayments')
          .select(
            'id, loan_id, amount_minor, paid_on, method, reference, '
            'recorded_by, status, dispute_reason',
          )
          .order('paid_on', ascending: false)
          .order('created_at', ascending: false),
      _db.from('profiles').select('id, name'),
    ]);
    final names = {for (final p in profiles) p['id']: p['name'] as String?};
    final summaryOf = {for (final s in summaries) s['loan_id']: s};
    final result = <Loan>[];
    for (final l in loans) {
      final youLent = l['lender_id'] == userId;
      final (side, other) = youLent
          ? ('lender', 'borrower')
          : ('borrower', 'lender');
      final s = summaryOf[l['id']];
      if (l['${side}_id'] != userId ||
          l['${side}_accepted_at'] == null ||
          s == null) {
        continue;
      }
      Paise? money(String key) => s[key] == null ? null : Paise(s[key] as int);
      result.add(
        Loan(
          id: l['id'] as String,
          counterparty:
              names[l['${other}_id']] ?? l['${other}_phone'] as String,
          youLent: youLent,
          principal: money('principal_minor')!,
          repaid: money('repaid_minor') ?? Paise.zero,
          startOn: _day(s['start_on'])!,
          installment: money('installment_minor'),
          dueDay: s['due_day'] as int?,
          installmentsPaid: s['installments_paid'] as int?,
          installmentsTotal: s['installments_total'] as int?,
          nextDueOn: _day(s['next_due_on']),
          endsOn: _day(s['ends_on']),
          onTrack: s['on_track'] as bool?,
          closed: s['closed_at'] != null,
          repayments: [
            for (final r in repayments)
              if (r['loan_id'] == l['id'])
                LoanRepayment(
                  id: r['id'] as String,
                  amount: Paise(r['amount_minor'] as int),
                  paidOn: _day(r['paid_on'])!,
                  method: switch (r['method']) {
                    final String m => RepaymentMethod.values.byName(m),
                    _ => null,
                  },
                  reference: r['reference'] as String?,
                  status: RepaymentStatus.values.byName(r['status'] as String),
                  recordedByYou: r['recorded_by'] == userId,
                  disputeReason: r['dispute_reason'] as String?,
                ),
          ],
        ),
      );
    }
    // Open loans first; sort is stable, so each group keeps its order.
    result.sort((a, b) => (a.closed ? 1 : 0) - (b.closed ? 1 : 0));
    return LoansData(
      today: DateTime(ist.year, ist.month, ist.day),
      loans: result,
      yourName: names[userId],
    );
  }

  @override
  Future<String> createLoan(
    NewLoan loan, {
    required String idempotencyKey,
  }) async {
    final id = await _call<String>('create_loan', {
      'p': {
        'idempotency_key': idempotencyKey,
        'direction': loan.youLent ? 'lent' : 'borrowed',
        'counterparty_phone': loan.counterpartyPhone,
        'principal_minor': loan.principal.value,
        'installment_minor': ?loan.installment?.value,
        'due_day': ?loan.dueDay,
        'start_on': loan.startOn.toIso8601String().substring(0, 10),
      },
    });
    return id!;
  }

  @override
  Future<String> recordRepayment(
    NewRepayment repayment, {
    required String idempotencyKey,
  }) async {
    final id = await _call<String>('record_repayment', {
      'p': {
        'loan_id': repayment.loanId,
        'idempotency_key': idempotencyKey,
        'amount_minor': repayment.amount.value,
        'method': ?repayment.method?.name,
        if (repayment.paidOn case final d?)
          'paid_on':
              '${d.year.toString().padLeft(4, '0')}-'
              '${d.month.toString().padLeft(2, '0')}-'
              '${d.day.toString().padLeft(2, '0')}',
        'reference': ?repayment.reference,
      },
    });
    return id!;
  }

  @override
  Future<void> confirmRepayment(
    String repaymentId, {
    required String idempotencyKey,
  }) => _call<void>('confirm_repayment', {
    'p_repayment_id': repaymentId,
    'p_idempotency_key': idempotencyKey,
  });

  @override
  Future<void> disputeRepayment(
    String repaymentId, {
    required String reason,
    required String idempotencyKey,
  }) => _call<void>('dispute_repayment', {
    'p_repayment_id': repaymentId,
    'p_reason': reason,
    'p_idempotency_key': idempotencyKey,
  });

  Future<T?> _call<T>(String fn, Map<String, Object?> params) async {
    try {
      return await _db.rpc<T>(fn, params: params);
    } on PostgrestException catch (e) {
      throw switch ((e.code, e.hint)) {
        ('PT409', _) => const IdempotencyConflict(),
        (_, 'overpayment') => const LoanRejected(LoanRejection.overpayment),
        (_, 'loan_closed') => const LoanRejected(LoanRejection.closed),
        (_, 'not_pending') => const LoanRejected(LoanRejection.notPending),
        (_, 'own_record') => const LoanRejected(LoanRejection.ownRecord),
        ('42501', _) => const LoanRejected(LoanRejection.notAllowed),
        ('22023', _) => const LoanRejected(LoanRejection.invalid),
        _ => e,
      };
    }
  }
}

/// Loans for the signed-in user through [supabaseClientProvider]; tests
/// override this. Rebuilt only when the user changes.
final loansRepositoryProvider = Provider<LoansRepository>((ref) {
  final userId = ref.watch(sessionProvider.select((s) => s?.user.id));
  if (userId == null) throw StateError('Loans needs a signed-in user');
  return SupabaseLoansRepository(
    ref.watch(supabaseClientProvider),
    userId: userId,
  );
});
