import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:settlo_core/money/paise.dart';
import 'package:settlo_core/supabase/providers.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// What a space is for; it picks the space's icon.
enum SpaceKind {
  /// Flatmates.
  flat,

  /// A trip.
  trip,

  /// One friend.
  friend,

  /// Anything else.
  other,
}

/// A space the signed-in user has accepted, as Home lists it.
@immutable
final class HomeSpace {
  /// A space row.
  const new({
    required this.id,
    required this.name,
    required this.kind,
    required this.balance,
    required this.people,
  });

  /// `spaces.id`.
  final String id;

  /// The space's name.
  final String name;

  /// What the space is for.
  final SpaceKind kind;

  /// Your balance in the space: positive is owed to you, negative you owe.
  final Paise balance;

  /// The other active members' names, in the order they were added.
  final List<String> people;
}

/// An open loan the signed-in user has accepted, as Home lists it.
@immutable
final class HomeLoan {
  /// A loan row.
  const new({
    required this.id,
    required this.counterparty,
    required this.youLent,
    required this.outstanding,
    this.installment,
    this.installmentsPaid,
    this.installmentsTotal,
    this.nextDueOn,
    this.pendingRepaymentId,
    this.pendingRepaymentAmount,
  });

  /// `loans.id`.
  final String id;

  /// The other party's name, or their number when it is not visible.
  final String counterparty;

  /// Whether you are the lender.
  final bool youLent;

  /// Principal not yet repaid (confirmed repayments only).
  final Paise outstanding;

  /// The monthly instalment; null for a flexible loan.
  final Paise? installment;

  /// Instalments repaid; null for a flexible loan.
  final int? installmentsPaid;

  /// Instalments in the schedule; null for a flexible loan.
  final int? installmentsTotal;

  /// The next instalment's date; null when none is left.
  final DateTime? nextDueOn;

  /// A pending repayment recorded by the other party, for Home review.
  final String? pendingRepaymentId;

  /// The amount of [pendingRepaymentId].
  final Paise? pendingRepaymentAmount;

  /// [outstanding] from your side: positive when you lent.
  Paise get balance => youLent ? outstanding : -outstanding;
}

/// What a [Claim] is attached to.
enum ClaimKind {
  /// A `space_members` row recorded against your number.
  spaceMember('space_member'),

  /// One side of a loan recorded against your number.
  loan('loan');

  new(this.wire);

  /// The `p_kind` the claim RPCs take.
  final String wire;
}

/// Something recorded against your number before you verified it. It is
/// someone else's word until you accept it; until then it stays out of
/// every balance.
@immutable
final class Claim {
  /// A claim to review.
  const new({
    required this.kind,
    required this.id,
    required this.title,
    required this.recordedBy,
    required this.amount,
    this.youLent = false,
    this.people = 0,
  });

  /// What it is attached to.
  final ClaimKind kind;

  /// The `space_members.id` or `loans.id` the claim RPCs take.
  final String id;

  /// The space's name, or the other party's for a loan.
  final String title;

  /// Who recorded it.
  final String recordedBy;

  /// Your balance in the space as recorded, or the loan's principal.
  final Paise amount;

  /// For a loan, whether it says you lent.
  final bool youLent;

  /// For a space, how many people are in it, you included.
  final int people;
}

/// Everything Home shows for the signed-in user.
@immutable
final class HomeData {
  /// Home's data.
  const new({
    required this.phone,
    required this.month,
    this.name,
    this.monthSpend = Paise.zero,
    this.spaces = const [],
    this.loans = const [],
    this.claims = const [],
  });

  /// Your verified number, E.164.
  final String phone;

  /// Your display name, if set.
  final String? name;

  /// The first day of the current month.
  final DateTime month;

  /// Your share of this month's spending across your accepted spaces.
  final Paise monthSpend;

  /// Accepted spaces.
  final List<HomeSpace> spaces;

  /// Accepted open loans.
  final List<HomeLoan> loans;

  /// Claims waiting for review.
  final List<Claim> claims;

  Iterable<Paise> get _balances => [
    for (final s in spaces) s.balance,
    for (final l in loans) l.balance,
  ];

  /// What others owe you, summed over spaces and loans.
  Paise get owed =>
      _balances.where((b) => b.value > 0).fold(Paise.zero, (sum, b) => sum + b);

  /// What you owe others, as a positive amount.
  Paise get owe =>
      _balances.where((b) => b.value < 0).fold(Paise.zero, (sum, b) => sum - b);

  /// [owed] minus [owe].
  Paise get net => owed - owe;

  /// Nothing recorded and nothing to review.
  bool get isEmpty => spaces.isEmpty && loans.isEmpty && claims.isEmpty;
}

/// Home's reads and the claim decisions. Features use this rather than the
/// Supabase client (ADR 0007); tests fake it.
///
/// Each decision takes an idempotency key made once per button and reused
/// on every retry of it, so a dropped connection never answers twice.
abstract interface class HomeRepository {
  /// Loads Home for the signed-in user.
  Future<HomeData> load();

  /// Accepts [claim]; it then counts in balances.
  Future<void> acceptClaim(Claim claim, {required String idempotencyKey});

  /// 'This isn't me': unlinks the number from [claim] for good.
  Future<void> rejectClaim(Claim claim, {required String idempotencyKey});
}

/// `accept_claim` / `reject_claim` parameters for [claim] (docs/api.md).
Map<String, Object?> claimParams(
  Claim claim, {
  required String idempotencyKey,
}) => {
  'p_kind': claim.kind.wire,
  'p_id': claim.id,
  'p_idempotency_key': idempotencyKey,
};

typedef _Row = Map<String, dynamic>;

/// PostgREST rows by table or view name, as RLS lets the caller read them.
/// The online repositories fetch them; the offline mirror stores them.
typedef Tables = Map<String, List<Map<String, dynamic>>>;

/// Who loan row [l] is with, from [userId]'s side, the [other] one
/// (`lender` or `borrower`): their profile name, else the name the
/// creator typed (`counterparty_name`, only theirs to see as a label),
/// else their phone.
String loanCounterparty(
  Map<String, dynamic> l,
  String other,
  Map<Object?, String?> names, {
  required String userId,
}) =>
    names[l['${other}_id']] ??
    (l['created_by'] == userId ? l['counterparty_name'] as String? : null) ??
    l['${other}_phone'] as String;

/// Home for [userId] from [t]: `space_members` (with `spaces`),
/// `space_member_balances`, `space_monthly_fairness` for [month], `loans`,
/// `loan_summaries`, pending `loan_repayments` and `profiles`.
HomeData homeFromRows(
  Tables t, {
  required String userId,
  required DateTime month,
}) {
  List<_Row> rows(String name) => t[name] ?? const [];
  final members = rows('space_members');
  final balances = rows('space_member_balances');
  final fairness = rows('space_monthly_fairness');
  final loans = rows('loans');
  final summaries = rows('loan_summaries');
  final repayments = rows('loan_repayments');
  final profiles = rows('profiles');
  final names = {for (final p in profiles) p['id']: p['name'] as String?};
  final me = profiles.where((p) => p['id'] == userId).firstOrNull;
  final balanceOf = {
    for (final b in balances) b['member_id']: Paise(b['balance_minor'] as int),
  };
  String label(_Row m) =>
      (m['name'] as String?) ?? names[m['user_id']] ?? m['phone'] as String;

  final spaces = <HomeSpace>[];
  final claims = <Claim>[];
  for (final m in members) {
    final space = m['spaces'] as _Row;
    if (m['user_id'] != userId ||
        m['left_at'] != null ||
        space['deleted_at'] != null) {
      continue;
    }
    final others = [
      for (final o in members)
        if (o['space_id'] == m['space_id'] &&
            o['id'] != m['id'] &&
            o['left_at'] == null)
          o,
    ];
    final balance = balanceOf[m['id']] ?? Paise.zero;
    if (m['accepted_at'] != null) {
      spaces.add(
        HomeSpace(
          id: m['space_id'] as String,
          name: space['name'] as String,
          kind: SpaceKind.values.byName(space['kind'] as String),
          balance: balance,
          people: [for (final o in others) label(o)],
        ),
      );
    } else {
      final creator = space['created_by'];
      final creatorRow = others.where((o) => o['user_id'] == creator);
      claims.add(
        Claim(
          kind: ClaimKind.spaceMember,
          id: m['id'] as String,
          title: space['name'] as String,
          recordedBy:
              names[creator] ?? creatorRow.map(label).firstOrNull ?? 'Someone',
          amount: balance,
          people: others.length + 1,
        ),
      );
    }
  }

  final accepted = {
    for (final m in members)
      if (m['user_id'] == userId && m['accepted_at'] != null) m['id'],
  };
  final monthSpend = fairness
      .where((f) => accepted.contains(f['member_id']))
      .fold(Paise.zero, (sum, f) => sum + Paise(f['fair_share_minor'] as int));

  final summaryOf = {for (final s in summaries) s['loan_id']: s};
  final homeLoans = <HomeLoan>[];
  for (final l in loans) {
    final youLent = l['lender_id'] == userId;
    if (l['closed_at'] != null || (!youLent && l['borrower_id'] != userId)) {
      continue;
    }
    final (side, other) = youLent
        ? ('lender', 'borrower')
        : ('borrower', 'lender');
    final counterparty = loanCounterparty(l, other, names, userId: userId);
    final s = summaryOf[l['id']] ?? const <String, dynamic>{};
    final pending = repayments
        .where(
          (r) =>
              r['loan_id'] == l['id'] &&
              r['recorded_by'] != userId &&
              r['status'] == 'pending',
        )
        .firstOrNull;
    Paise? money(String key) => s[key] == null ? null : Paise(s[key] as int);
    if (l['${side}_accepted_at'] != null) {
      homeLoans.add(
        HomeLoan(
          id: l['id'] as String,
          counterparty: counterparty,
          youLent: youLent,
          outstanding: money('outstanding_minor') ?? Paise.zero,
          installment: money('installment_minor'),
          installmentsPaid: s['installments_paid'] as int?,
          installmentsTotal: s['installments_total'] as int?,
          nextDueOn: switch (s['next_due_on']) {
            final String d => DateTime.parse(d),
            _ => null,
          },
          pendingRepaymentId: pending?['id'] as String?,
          pendingRepaymentAmount: switch (pending?['amount_minor']) {
            final int amount => Paise(amount),
            _ => null,
          },
        ),
      );
    } else {
      claims.add(
        Claim(
          kind: ClaimKind.loan,
          id: l['id'] as String,
          title: counterparty,
          recordedBy: names[l['created_by']] ?? counterparty,
          amount: money('principal_minor') ?? Paise.zero,
          youLent: youLent,
        ),
      );
    }
  }

  return HomeData(
    phone: (me?['phone'] as String?) ?? '',
    name: me?['name'] as String?,
    month: month,
    monthSpend: monthSpend,
    spaces: spaces,
    loans: homeLoans,
    claims: claims,
  );
}

/// [HomeRepository] over PostgREST: the tables and views RLS lets the
/// caller read, joined on device, and the `accept_claim` / `reject_claim`
/// RPCs (docs/api.md).
final class SupabaseHomeRepository implements HomeRepository {
  /// Reads as [userId] through [_db]; [now] picks the month.
  const new(this._db, {required this.userId, this.now = DateTime.now});

  final SupabaseClient _db;

  /// The signed-in user's id.
  final String userId;

  /// The clock.
  final DateTime Function() now;

  @override
  Future<HomeData> load() async {
    final today = now();
    final month = DateTime(today.year, today.month);
    final monthKey =
        '${month.year}-${month.month.toString().padLeft(2, '0')}-01';
    final [
      members,
      balances,
      fairness,
      loans,
      summaries,
      repayments,
      profiles,
    ] = await Future.wait<List<_Row>>([
      _db
          .from('space_members')
          .select(
            'id, space_id, user_id, name, phone, accepted_at, left_at, '
            'spaces(name, kind, created_by, deleted_at)',
          )
          .order('created_at'),
      _db.from('space_member_balances').select('member_id, balance_minor'),
      _db
          .from('space_monthly_fairness')
          .select('member_id, fair_share_minor')
          .eq('month', monthKey),
      _db
          .from('loans')
          .select(
            'id, lender_id, borrower_id, lender_phone, borrower_phone, '
            'lender_accepted_at, borrower_accepted_at, created_by, '
            'counterparty_name, closed_at',
          )
          .order('created_at'),
      _db
          .from('loan_summaries')
          .select(
            'loan_id, principal_minor, outstanding_minor, '
            'installment_minor, installments_total, installments_paid, '
            'next_due_on',
          ),
      _db
          .from('loan_repayments')
          .select('id, loan_id, amount_minor, recorded_by, status')
          .eq('status', 'pending')
          .order('paid_on', ascending: false)
          .order('created_at', ascending: false),
      _db.from('profiles').select('id, name, phone'),
    ]);

    return homeFromRows(
      {
        'space_members': members,
        'space_member_balances': balances,
        'space_monthly_fairness': fairness,
        'loans': loans,
        'loan_summaries': summaries,
        'loan_repayments': repayments,
        'profiles': profiles,
      },
      userId: userId,
      month: month,
    );
  }

  @override
  Future<void> acceptClaim(Claim claim, {required String idempotencyKey}) =>
      _db.rpc<void>(
        'accept_claim',
        params: claimParams(claim, idempotencyKey: idempotencyKey),
      );

  @override
  Future<void> rejectClaim(Claim claim, {required String idempotencyKey}) =>
      _db.rpc<void>(
        'reject_claim',
        params: claimParams(claim, idempotencyKey: idempotencyKey),
      );
}

/// Home's data for the signed-in user through [supabaseClientProvider];
/// tests override this. Rebuilt only when the user changes, not on every
/// token refresh.
final homeRepositoryProvider = Provider<HomeRepository>((ref) {
  final userId = ref.watch(sessionProvider.select((s) => s?.user.id));
  if (userId == null) throw StateError('Home needs a signed-in user');
  return SupabaseHomeRepository(
    ref.watch(supabaseClientProvider),
    userId: userId,
  );
});
