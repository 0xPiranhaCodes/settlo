import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:settlo_core/money/paise.dart';
import 'package:settlo_core/supabase/providers.dart';
import 'package:settlo_core/theme/colors.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// What an [ActivityEntry] is about (`activity_feed.kind`).
enum ActivityKind {
  /// Spending in a space.
  expense,

  /// A settle-up in a space.
  settlement,

  /// A loan itself: created or closed.
  loan,

  /// A loan repayment.
  repayment,

  /// A number that said a membership or loan wasn't theirs.
  member,
}

/// What happened (`activity.action`).
enum ActivityAction {
  /// Added or recorded.
  created,

  /// Changed; the entry carries the values before.
  edited,

  /// Deleted.
  deleted,

  /// Brought back after a delete.
  restored,

  /// A repayment recorded by one side.
  recorded,

  /// Confirmed by the other side.
  confirmed,

  /// Disputed by the other side.
  disputed,

  /// A claim declined ('This isn't me').
  rejected,

  /// A loan repaid in full.
  closed,
}

/// Where a settle-up or repayment stands now.
enum ActivityStatus {
  /// Waiting for the other side.
  pending,

  /// Confirmed; it counts.
  confirmed,

  /// Disputed; it never counts.
  disputed,

  /// Deleted before it was answered.
  deleted,
}

/// One line of the Activity feed (`activity_feed`, docs/api.md).
@immutable
final class ActivityEntry {
  /// An `activity_feed` row.
  const new({
    required this.id,
    required this.at,
    required this.kind,
    required this.action,
    required this.byYou,
    this.spaceId,
    this.spaceName,
    this.loanId,
    this.actor,
    this.counterparty,
    this.description,
    this.amount,
    this.beforeDescription,
    this.beforeAmount,
    this.status,
    this.toYou,
    this.linkOnly = false,
  });

  /// `activity.id`; with [at], the feed's cursor.
  final int id;

  /// When it happened; the feed runs newest first by this, then [id].
  final DateTime at;

  /// What it is about.
  final ActivityKind kind;

  /// What happened.
  final ActivityAction action;

  /// Whether you did it.
  final bool byYou;

  /// The space, for space rows.
  final String? spaceId;

  /// The space's name, for space rows.
  final String? spaceName;

  /// The loan, for loan and repayment rows.
  final String? loanId;

  /// Who did it, when it wasn't you.
  final String? actor;

  /// The other party of a loan.
  final String? counterparty;

  /// The expense's description; for a declined claim, the number.
  final String? description;

  /// The amount after the change; a loan's principal.
  final Paise? amount;

  /// For an edit, the description before.
  final String? beforeDescription;

  /// For an edit, the amount before.
  final Paise? beforeAmount;

  /// A settle-up's or repayment's state now.
  final ActivityStatus? status;

  /// For a settle-up or repayment you are part of: whether the money came
  /// to you (true) or went from you (false).
  final bool? toYou;

  /// This row records that a bearer declined only one link, not the invite.
  final bool linkOnly;

  /// The amount's colour: mint in your favour, coral against you, once it
  /// counts. Disputed or deleted money is grey; everything else, such as
  /// spending or a transfer still waiting, is uncoloured.
  MoneyTone get tone => switch ((status, toYou)) {
    (ActivityStatus.disputed || ActivityStatus.deleted, _) => MoneyTone.settled,
    (ActivityStatus.confirmed, true) => MoneyTone.owedToYou,
    (ActivityStatus.confirmed, false) => MoneyTone.youOwe,
    _ => MoneyTone.neutral,
  };
}

/// A settle-up or repayment waiting for your answer (`needs_you`).
@immutable
final class PendingAnswer {
  /// A `needs_you` row.
  const new({
    required this.id,
    required this.isRepayment,
    required this.counterparty,
    required this.amount,
    required this.paidOn,
    required this.recordedAt,
    this.spaceId,
    this.spaceName,
    this.loanId,
  });

  /// The repayment's id, or the settle-up's expense id.
  final String id;

  /// A loan repayment; otherwise a settle-up in a space.
  final bool isRepayment;

  /// Who says they paid you.
  final String counterparty;

  /// How much.
  final Paise amount;

  /// The day they paid.
  final DateTime paidOn;

  /// When it was recorded.
  final DateTime recordedAt;

  /// The settle-up's space.
  final String? spaceId;

  /// The settle-up's space name.
  final String? spaceName;

  /// The repayment's loan.
  final String? loanId;
}

/// Activity's reads. Features use this rather than the Supabase client
/// (docs/decisions/2026-11-09-interim-online-repositories.md); tests fake
/// it. Answering goes through the spaces and loans flows.
abstract interface class ActivityRepository {
  /// Up to [limit] feed entries, newest first by time then id, after
  /// entry [before] when given (keyset on that pair). Pages are strict and
  /// stable for rows committed before the first page; a change committed
  /// after you paged past its time shows only once you reload from the top.
  Future<List<ActivityEntry>> feed({required int limit, ActivityEntry? before});

  /// What waits for your answer, newest first.
  Future<List<PendingAnswer>> needsYou();
}

/// [ActivityRepository] over the `activity_feed` RPC and `needs_you` view
/// (docs/api.md).
final class SupabaseActivityRepository implements ActivityRepository {
  /// Reads through [_db] as the signed-in user.
  const new(this._db);

  final SupabaseClient _db;

  @override
  Future<List<ActivityEntry>> feed({
    required int limit,
    ActivityEntry? before,
  }) async {
    final rows = await _db.rpc<List<dynamic>>(
      'activity_feed',
      params: {
        'p_limit': limit,
        if (before != null) ...{
          // Microseconds survive the round trip, so the cursor is exact.
          'p_before_at': before.at.toUtc().toIso8601String(),
          'p_before_id': before.id,
        },
      },
    );
    Paise? money(Object? v) => v is int ? Paise(v) : null;
    return [
      for (final r in rows.cast<Map<String, dynamic>>())
        ActivityEntry(
          id: r['id'] as int,
          at: DateTime.parse(r['created_at'] as String),
          kind: ActivityKind.values.byName(r['kind'] as String),
          action: ActivityAction.values.byName(r['action'] as String),
          byYou: r['by_me'] as bool,
          spaceId: r['space_id'] as String?,
          spaceName: r['space_name'] as String?,
          loanId: r['loan_id'] as String?,
          actor: r['actor_name'] as String?,
          counterparty: r['counterparty'] as String?,
          description: r['description'] as String?,
          amount: money(r['amount_minor']),
          beforeDescription: r['before_description'] as String?,
          beforeAmount: money(r['before_amount_minor']),
          status: switch (r['status']) {
            final String s => ActivityStatus.values.byName(s),
            _ => null,
          },
          toYou: switch (r['my_side']) {
            'in' => true,
            'out' => false,
            _ => null,
          },
          linkOnly: r['link_only'] as bool? ?? false,
        ),
    ];
  }

  @override
  Future<List<PendingAnswer>> needsYou() async {
    final rows = await _db
        .from('needs_you')
        .select(
          'kind, id, space_id, space_name, loan_id, counterparty, '
          'amount_minor, paid_on, created_at',
        )
        .order('created_at', ascending: false);
    return [
      for (final r in rows)
        PendingAnswer(
          id: r['id'] as String,
          isRepayment: r['kind'] == 'repayment',
          counterparty: r['counterparty'] as String,
          amount: Paise(r['amount_minor'] as int),
          paidOn: DateTime.parse(r['paid_on'] as String),
          recordedAt: DateTime.parse(r['created_at'] as String),
          spaceId: r['space_id'] as String?,
          spaceName: r['space_name'] as String?,
          loanId: r['loan_id'] as String?,
        ),
    ];
  }
}

/// Activity for the signed-in user through [supabaseClientProvider]; tests
/// override this.
final activityRepositoryProvider = Provider<ActivityRepository>(
  (ref) => SupabaseActivityRepository(ref.watch(supabaseClientProvider)),
);
