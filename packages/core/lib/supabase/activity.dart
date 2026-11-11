import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:settlo_core/export/names.dart';
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
  /// A polite nudge from the other party.
  reminded,

  /// An instalment missed yesterday.
  due,

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

/// Which part of the feed to read: one space's rows, loan rows, or, with
/// neither, everything ([allActivity]).
typedef ActivityFilter = ({String? spaceId, bool loansOnly});

/// The whole feed.
const ActivityFilter allActivity = (spaceId: null, loansOnly: false);

/// A member's 'Question this' note on an edit: whether you asked, else who
/// did, the note with phone numbers redacted, and when it was asked (null
/// while yours is still queued on this device).
typedef ActivityQuestion = ({
  bool byYou,
  String? name,
  String note,
  DateTime? at,
});

/// The longest 'Question this' note, as `question_activity` allows.
const questionMaxLength = 280;

/// How many feed entries count as unread at most: `activity_feed`'s largest
/// page, which is what the offline mirror keeps.
const unreadWindow = 100;

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
    this.questions = const [],
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

  /// Members' 'Question this' notes on this edit, oldest first.
  final List<ActivityQuestion> questions;

  /// Whether this is in [filter], as `activity_feed` decides it.
  bool isIn(ActivityFilter filter) =>
      (filter.spaceId == null || spaceId == filter.spaceId) &&
      (!filter.loansOnly || (loanId != null && filter.spaceId == null));

  /// Whether you may question this: someone else's edit in a space, which
  /// you have not questioned yet.
  bool get canQuestion =>
      action == ActivityAction.edited &&
      !byYou &&
      spaceId != null &&
      !questions.any((q) => q.byYou);

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
  /// [filter] narrows the feed without changing that.
  Future<List<ActivityEntry>> feed({
    required int limit,
    ActivityEntry? before,
    ActivityFilter filter = allActivity,
  });

  /// How many of the newest [unreadWindow] entries are unread ([unreadIn])
  /// since you last looked, on any of your devices.
  Future<int> unread();

  /// Marks everything in the newest [unreadWindow] entries as seen,
  /// questions included.
  Future<void> markSeen();

  /// Leaves [note] on [entry], an edit, for its editor; the space's members
  /// see it on that row. Asking again replaces your note.
  Future<void> question(ActivityEntry entry, String note);

  /// What waits for your answer, newest first.
  Future<List<PendingAnswer>> needsYou();
}

/// Feed entries from `activity_feed` rows, in their order.
List<ActivityEntry> activityFromRows(List<Map<String, dynamic>> rows) {
  Paise? money(Object? v) => v is int ? Paise(v) : null;
  return [
    for (final r in rows)
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
        questions: [
          for (final q
              in (r['questions'] as List<dynamic>? ?? const [])
                  .cast<Map<String, dynamic>>())
            (
              byYou: q['by_me'] as bool,
              name: q['name'] as String?,
              // Again here: the server only knows ASCII digits, and another
              // client may not have redacted at all.
              note: redactPhones(q['note'] as String),
              at: switch (q['created_at']) {
                final String at => DateTime.parse(at),
                _ => null,
              },
            ),
        ],
      ),
  ];
}

/// How many of [entries] are unread, that is newer than [seenAt] (or all
/// of them when nothing was seen yet): each entry of someone else's, and
/// each question someone asked about an edit of yours. A question rings
/// only for the editor it is addressed to, never for the space's other
/// members.
int unreadIn(Iterable<ActivityEntry> entries, DateTime? seenAt) {
  bool isNew(DateTime? at) =>
      at != null && (seenAt == null || at.isAfter(seenAt));
  return entries.fold(
    0,
    (n, e) =>
        n +
        (e.byYou
            ? e.questions.where((q) => !q.byYou && isNew(q.at)).length
            : isNew(e.at)
            ? 1
            : 0),
  );
}

/// The time of the newest thing in [entries], an entry or a question on
/// one: what seeing all of them moves the cursor to.
DateTime? newestIn(Iterable<ActivityEntry> entries) =>
    [
      for (final e in entries) ...[e.at, for (final q in e.questions) ?q.at],
    ].fold(
      null,
      (newest, at) => newest == null || at.isAfter(newest) ? at : newest,
    );

/// When the caller last saw the feed, from their `activity_seen` rows (one
/// at most).
DateTime? seenAtFromRows(List<Map<String, dynamic>> rows) =>
    switch (rows.firstOrNull?['seen_at']) {
      final String at => DateTime.parse(at),
      _ => null,
    };

/// `mark_activity_seen`'s arguments for having seen everything up to [at].
Map<String, Object?> markSeenParams(DateTime at) => {
  // Microseconds survive the round trip, so the cursor is exact.
  'p_at': at.toUtc().toIso8601String(),
};

/// `question_activity`'s arguments. Phone numbers are redacted before the
/// note leaves the device.
Map<String, Object?> questionParams(ActivityEntry entry, String note) => {
  'p_activity_id': entry.id,
  'p_note': redactPhones(note.trim()),
};

/// What waits for you from `needs_you` rows, in their order.
List<PendingAnswer> needsYouFromRows(List<Map<String, dynamic>> rows) => [
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
    ActivityFilter filter = allActivity,
  }) async {
    final rows = await _db.rpc<List<dynamic>>(
      'activity_feed',
      params: {
        'p_limit': limit,
        'p_space_id': ?filter.spaceId,
        if (filter.loansOnly) 'p_loans_only': true,
        if (before != null) ...{
          // Microseconds survive the round trip, so the cursor is exact.
          'p_before_at': before.at.toUtc().toIso8601String(),
          'p_before_id': before.id,
        },
      },
    );
    return activityFromRows(rows.cast());
  }

  @override
  Future<int> unread() async {
    final seen = await _db.from('activity_seen').select('seen_at');
    return unreadIn(await feed(limit: unreadWindow), seenAtFromRows(seen));
  }

  @override
  Future<void> markSeen() async {
    final newest = newestIn(await feed(limit: unreadWindow));
    if (newest == null) return;
    await _db.rpc<void>('mark_activity_seen', params: markSeenParams(newest));
  }

  @override
  Future<void> question(ActivityEntry entry, String note) =>
      _db.rpc<void>('question_activity', params: questionParams(entry, note));

  @override
  Future<List<PendingAnswer>> needsYou() async {
    final rows = await _db
        .from('needs_you')
        .select(
          'kind, id, space_id, space_name, loan_id, counterparty, '
          'amount_minor, paid_on, created_at',
        )
        .order('created_at', ascending: false);
    return needsYouFromRows(rows);
  }
}

/// Activity for the signed-in user through [supabaseClientProvider]; tests
/// override this.
final activityRepositoryProvider = Provider<ActivityRepository>(
  (ref) => SupabaseActivityRepository(ref.watch(supabaseClientProvider)),
);

/// The bell's count: [ActivityRepository.unread], reloaded whenever
/// [ledgerRevisionProvider] is bumped and whenever the signed-in user
/// changes.
final FutureProvider<int> activityUnreadProvider =
    FutureProvider.autoDispose<int>((ref) {
      ref
        ..watch(ledgerRevisionProvider)
        ..watch(sessionProvider.select((s) => s?.user.id));
      return ref.watch(activityRepositoryProvider).unread();
    });
