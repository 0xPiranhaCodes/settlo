import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:settlo_core/money/paise.dart';
import 'package:settlo_core/money/simplify.dart';
import 'package:settlo_core/supabase/home.dart';
import 'package:settlo_core/supabase/providers.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// An active member of a space, as the Spaces screens show them.
@immutable
final class SpaceMember {
  /// A member row.
  const new({
    required this.id,
    required this.name,
    required this.phone,
    this.isYou = false,
    this.isOwner = false,
    this.joined = true,
    this.balance = Paise.zero,
    this.monthPaid = Paise.zero,
    this.upiId,
  });

  /// `space_members.id`.
  final String id;

  /// The creator's label for them, their profile name, or their number.
  final String name;

  /// Their number, E.164.
  final String phone;

  /// Whether this is the signed-in user.
  final bool isYou;

  /// Whether they own the space.
  final bool isOwner;

  /// Whether they have verified their number and accepted the space.
  final bool joined;

  /// Their balance in the space: positive is owed to them.
  final Paise balance;

  /// What they paid towards this month's spending.
  final Paise monthPaid;

  /// Their UPI id (`profiles.upi_id`); null until they join and add one.
  final String? upiId;
}

/// A space the signed-in user has accepted.
@immutable
final class SpaceSummary {
  /// A space; [members] includes you.
  const new({
    required this.id,
    required this.name,
    required this.kind,
    required this.members,
    this.departed = const [],
    this.month,
    this.monthTotal = Paise.zero,
    this.yourFairShare = Paise.zero,
    this.hasExpenses = false,
    this.pendingFromYou = const [],
  });

  /// `spaces.id`.
  final String id;

  /// The space's name.
  final String name;

  /// What the space is for.
  final SpaceKind kind;

  /// Active members in the order they were added; exactly one is you.
  final List<SpaceMember> members;

  /// Members who left. They are not in the space any more, but what they
  /// paid still counts in its history and this month's paid bar.
  final List<SpaceMember> departed;

  /// The first day of the current month; null when not loaded.
  final DateTime? month;

  /// The space's spending this month.
  final Paise monthTotal;

  /// Your share of [monthTotal].
  final Paise yourFairShare;

  /// Whether anything has ever been recorded in the space.
  final bool hasExpenses;

  /// Settle-ups you paid that wait for their payee to confirm (#78). They
  /// do not count in balances yet, but [payments] does not offer them
  /// again; a disputed one is no longer pending, so its debt returns.
  final List<Payment<SpaceMember>> pendingFromYou;

  /// The signed-in user's row.
  SpaceMember get you => members.firstWhere((m) => m.isYou);

  /// Everyone but you.
  List<SpaceMember> get others => [
    for (final m in members)
      if (!m.isYou) m,
  ];

  /// Your balance in the space.
  Paise get balance => you.balance;

  /// The fewest payments that settle everyone, members who left
  /// included (ADR 0003): at most one fewer than the people owed or
  /// owing. Counts [pendingFromYou] as if confirmed, so you are never
  /// offered a payment you already made.
  List<Payment<SpaceMember>> get payments {
    final nets = {
      for (final m in [...members, ...departed]) m.id: m.balance,
    };
    for (final p in pendingFromYou) {
      if (nets.containsKey(p.from.id) && nets.containsKey(p.to.id)) {
        nets[p.from.id] = nets[p.from.id]! + p.amount;
        nets[p.to.id] = nets[p.to.id]! - p.amount;
      }
    }
    final byId = {
      for (final m in [...members, ...departed]) m.id: m,
    };
    // Balances always sum to zero; never let a bad read crash a screen.
    return nets.values.fold(0, (s, b) => s + b.value) == 0
        ? [
            for (final p in simplifyDebts(nets))
              (from: byId[p.from]!, to: byId[p.to]!, amount: p.amount),
          ]
        : const [];
  }
}

/// Someone to add to a new space: their E.164 number and your label.
typedef NewSpaceMember = ({String phone, String name});

/// Spaces' reads and writes. Features use this rather than the Supabase
/// client (docs/decisions/2026-11-09-interim-online-repositories.md);
/// tests fake it.
abstract interface class SpacesRepository {
  /// The signed-in user's accepted spaces, oldest first.
  Future<List<SpaceSummary>> load();

  /// Creates a space with you as owner and returns its id. Retrying with
  /// the same [idempotencyKey] and payload returns the same id; a changed
  /// payload throws [IdempotencyConflict].
  Future<String> create({
    required String name,
    required SpaceKind kind,
    required List<NewSpaceMember> members,
    required String idempotencyKey,
  });
}

/// The idempotency key was already used with a different payload
/// (`PT409`): the first attempt was saved, so a retry with edited details
/// cannot be.
final class IdempotencyConflict implements Exception {
  /// A conflict.
  const new();
}

/// A fresh random (v4) UUID, generated once per mutation on device and
/// reused on every retry of it (ADR 0004).
String newIdempotencyKey([Random? random]) {
  final r = random ?? Random.secure();
  final b = List<int>.generate(16, (_) => r.nextInt(256));
  b[6] = b[6] & 0x0f | 0x40;
  b[8] = b[8] & 0x3f | 0x80;
  final h = [for (final x in b) x.toRadixString(16).padLeft(2, '0')].join();
  return '${h.substring(0, 8)}-${h.substring(8, 12)}-${h.substring(12, 16)}-'
      '${h.substring(16, 20)}-${h.substring(20)}';
}

typedef _Row = Map<String, dynamic>;

/// [SpacesRepository] over PostgREST: the tables and views RLS lets the
/// caller read, joined on device, and the `create_space` RPC
/// (docs/api.md).
final class SupabaseSpacesRepository implements SpacesRepository {
  /// Reads as [userId] through [_db]; [now] picks the month.
  const new(this._db, {required this.userId, this.now = DateTime.now});

  final SupabaseClient _db;

  /// The signed-in user's id.
  final String userId;

  /// The clock.
  final DateTime Function() now;

  @override
  Future<List<SpaceSummary>> load() async {
    final today = now();
    final month = DateTime(today.year, today.month);
    final monthKey =
        '${month.year}-${month.month.toString().padLeft(2, '0')}-01';
    final [
      members,
      balances,
      fairness,
      profiles,
      pending,
    ] = await Future.wait<List<_Row>>([
      _db
          .from('space_members')
          .select(
            'id, space_id, user_id, name, phone, role, accepted_at, '
            'left_at, spaces(name, kind, deleted_at)',
          )
          .order('created_at'),
      _db
          .from('space_member_balances')
          .select('member_id, paid_minor, balance_minor'),
      _db
          .from('space_monthly_fairness')
          .select('member_id, paid_minor, fair_share_minor, month_total_minor')
          .eq('month', monthKey),
      _db.from('profiles').select('id, name, upi_id'),
      _db
          .from('pending_settlements')
          .select('payer_member_id, payee_member_id, amount_minor'),
    ]);

    final names = {for (final p in profiles) p['id']: p['name'] as String?};
    final upiIds = {for (final p in profiles) p['id']: p['upi_id'] as String?};
    final balanceOf = {for (final b in balances) b['member_id']: b};
    final fairnessOf = {for (final f in fairness) f['member_id']: f};
    Paise money(_Row? row, String key) => Paise((row?[key] as int?) ?? 0);

    final spaces = <SpaceSummary>[];
    for (final mine in members) {
      final space = mine['spaces'] as _Row;
      if (mine['user_id'] != userId ||
          mine['accepted_at'] == null ||
          mine['left_at'] != null ||
          space['deleted_at'] != null) {
        continue;
      }
      final rows = [
        for (final m in members)
          if (m['space_id'] == mine['space_id']) m,
      ];
      SpaceMember member(_Row m) => SpaceMember(
        id: m['id'] as String,
        name:
            (m['name'] as String?) ??
            names[m['user_id']] ??
            m['phone'] as String,
        phone: m['phone'] as String,
        isYou: m['id'] == mine['id'],
        isOwner: m['role'] == 'owner',
        joined: m['accepted_at'] != null,
        balance: money(balanceOf[m['id']], 'balance_minor'),
        monthPaid: money(fairnessOf[m['id']], 'paid_minor'),
        upiId: upiIds[m['user_id']],
      );
      final you = fairnessOf[mine['id']];
      final byId = {for (final m in rows) m['id']: member(m)};
      spaces.add(
        SpaceSummary(
          id: mine['space_id'] as String,
          name: space['name'] as String,
          kind: SpaceKind.values.byName(space['kind'] as String),
          month: month,
          monthTotal: money(you, 'month_total_minor'),
          yourFairShare: money(you, 'fair_share_minor'),
          // Members who left count too: their payments are still history.
          hasExpenses: rows.any(
            (m) => money(balanceOf[m['id']], 'paid_minor').value > 0,
          ),
          members: [
            for (final m in rows)
              if (m['left_at'] == null) byId[m['id']]!,
          ],
          departed: [
            for (final m in rows)
              if (m['left_at'] != null) byId[m['id']]!,
          ],
          pendingFromYou: [
            for (final p in pending)
              if (byId[p['payee_member_id']] case final to?
                  when p['payer_member_id'] == mine['id'])
                (
                  from: byId[mine['id']]!,
                  to: to,
                  amount: Paise(p['amount_minor'] as int),
                ),
          ],
        ),
      );
    }
    return spaces;
  }

  @override
  Future<String> create({
    required String name,
    required SpaceKind kind,
    required List<NewSpaceMember> members,
    required String idempotencyKey,
  }) async {
    try {
      return await _db.rpc<String>(
        'create_space',
        params: {
          'p_name': name,
          'p_kind': kind.name,
          'p_members': [
            for (final m in members) {'phone': m.phone, 'name': m.name},
          ],
          'p_idempotency_key': idempotencyKey,
        },
      );
    } on PostgrestException catch (e) {
      if (e.code == 'PT409') throw const IdempotencyConflict();
      rethrow;
    }
  }
}

/// Spaces for the signed-in user through [supabaseClientProvider]; tests
/// override this. Rebuilt only when the user changes.
final spacesRepositoryProvider = Provider<SpacesRepository>((ref) {
  final userId = ref.watch(sessionProvider.select((s) => s?.user.id));
  if (userId == null) throw StateError('Spaces needs a signed-in user');
  return SupabaseSpacesRepository(
    ref.watch(supabaseClientProvider),
    userId: userId,
  );
});
