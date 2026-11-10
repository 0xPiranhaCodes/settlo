import 'dart:convert';

import 'package:drift/drift.dart';
import 'package:drift_flutter/drift_flutter.dart';
import 'package:settlo_core/settlo_core.dart';

/// A queued write (ADR 0004): the RPC `kind` with its exact `params`,
/// sent with `key` on every attempt. `applied` means the server accepted
/// it and the next refresh will drop it.
typedef Mutation = ({
  int id,
  String key,
  String kind,
  Map<String, dynamic> params,
  DateTime createdAt,
  int attempts,
  bool applied,
});

/// The on-device store: the server rows each signed-in user can read
/// (`mirror`), their queued writes (`pending_mutations`), and the server
/// ids of what those writes created (`local_ids`), kept past refreshes so
/// a screen still holding a device-made id can save against it. Every row
/// is scoped by `owner`, the auth user id.
///
/// Raw SQL, no codegen: the mirror keeps PostgREST rows as JSON so the
/// joins in `settlo_core` run on them unchanged (ADR 0012).
final class LocalDb extends GeneratedDatabase {
  /// A database on [executor]; tests pass an in-memory one.
  new(super.executor);

  /// The app's database file, `settlo.sqlite`.
  factory open() => LocalDb(driftDatabase(name: 'settlo'));

  @override
  Iterable<TableInfo<Table, dynamic>> get allTables => const [];

  // Upgrades: the mirror is disposable and may be dropped and refetched;
  // pending_mutations is user data and only takes additive `from < n` steps.
  @override
  int get schemaVersion => 1;

  @override
  MigrationStrategy get migration => MigrationStrategy(
    onCreate: (_) async {
      await customStatement(
        'CREATE TABLE mirror ( '
        'owner TEXT NOT NULL, source TEXT NOT NULL, rows TEXT NOT NULL, '
        'PRIMARY KEY (owner, source))',
      );
      await customStatement(
        'CREATE TABLE pending_mutations ( '
        'id INTEGER PRIMARY KEY AUTOINCREMENT, '
        'owner TEXT NOT NULL, '
        'idempotency_key TEXT NOT NULL UNIQUE, '
        'kind TEXT NOT NULL, '
        'payload TEXT NOT NULL, '
        'created_at INTEGER NOT NULL, '
        'attempts INTEGER NOT NULL DEFAULT 0, '
        'last_error TEXT, '
        "status TEXT NOT NULL DEFAULT 'pending')",
      );
      await customStatement(
        'CREATE TABLE local_ids ( '
        'owner TEXT NOT NULL, local_id TEXT NOT NULL, '
        'server_id TEXT NOT NULL, PRIMARY KEY (owner, local_id))',
      );
    },
  );

  /// [owner]'s mirrored rows by source.
  Future<Tables> mirror(String owner) async {
    final rows = await customSelect(
      'SELECT source, rows FROM mirror WHERE owner = ?',
      variables: [Variable(owner)],
    ).get();
    return {
      for (final r in rows)
        r.read<String>('source'): (jsonDecode(r.read<String>('rows')) as List)
            .cast<Map<String, dynamic>>(),
    };
  }

  /// [owner]'s queue, oldest first.
  Future<List<Mutation>> mutations(String owner) async {
    final rows = await customSelect(
      'SELECT * FROM pending_mutations WHERE owner = ? ORDER BY id',
      variables: [Variable(owner)],
    ).get();
    return [
      for (final r in rows)
        (
          id: r.read<int>('id'),
          key: r.read<String>('idempotency_key'),
          kind: r.read<String>('kind'),
          params: jsonDecode(r.read<String>('payload')) as Map<String, dynamic>,
          createdAt: DateTime.fromMillisecondsSinceEpoch(
            r.read<int>('created_at'),
          ),
          attempts: r.read<int>('attempts'),
          applied: r.read<String>('status') == 'applied',
        ),
    ];
  }

  /// Queues [kind] with [params] under [key]. Queuing the same key and
  /// payload again does nothing; another payload under a queued key
  /// throws [IdempotencyConflict], as the server would.
  Future<void> enqueue(
    String owner,
    String key,
    String kind,
    Map<String, Object?> params,
    DateTime now,
  ) => transaction(() async {
    final payload = jsonEncode(params);
    final existing = await customSelect(
      'SELECT owner, kind, payload FROM pending_mutations '
      'WHERE idempotency_key = ?',
      variables: [Variable(key)],
    ).getSingleOrNull();
    if (existing != null) {
      if (existing.read<String>('owner') != owner ||
          existing.read<String>('kind') != kind ||
          existing.read<String>('payload') != payload) {
        throw const IdempotencyConflict();
      }
      return;
    }
    await customInsert(
      'INSERT INTO pending_mutations '
      '(owner, idempotency_key, kind, payload, created_at) '
      'VALUES (?, ?, ?, ?, ?)',
      variables: [
        Variable(owner),
        Variable(key),
        Variable(kind),
        Variable(payload),
        Variable(now.millisecondsSinceEpoch),
      ],
    );
  });

  /// The server accepted [owner]'s mutation [id]; [ids] maps the local
  /// ids it created to the server's.
  Future<void> markApplied(String owner, int id, Map<String, String> ids) =>
      transaction(() async {
        await customUpdate(
          "UPDATE pending_mutations SET status = 'applied' WHERE id = ?",
          variables: [Variable(id)],
        );
        for (final MapEntry(:key, :value) in ids.entries) {
          await customInsert(
            'INSERT OR REPLACE INTO local_ids (owner, local_id, server_id) '
            'VALUES (?, ?, ?)',
            variables: [Variable(owner), Variable(key), Variable(value)],
          );
        }
      });

  /// [owner]'s device-made ids, mapped to the server's.
  Future<Map<String, String>> localIds(String owner) async => {
    for (final r in await customSelect(
      'SELECT local_id, server_id FROM local_ids WHERE owner = ?',
      variables: [Variable(owner)],
    ).get())
      r.read<String>('local_id'): r.read<String>('server_id'),
  };

  /// Mutation [id] could not reach the server; it stays queued.
  Future<void> markFailed(int id, String error) => customUpdate(
    'UPDATE pending_mutations SET attempts = attempts + 1, last_error = ? '
    'WHERE id = ?',
    variables: [Variable(error), Variable(id)],
  );

  /// Removes mutation [id], which rolls back its optimistic change.
  Future<void> drop(int id) => customUpdate(
    'DELETE FROM pending_mutations WHERE id = ?',
    variables: [Variable(id)],
  );

  /// Replaces [owner]'s mirror with [tables] and drops their applied
  /// mutations, which [tables] now include, in one transaction. True when
  /// that changed what the mirror shows.
  Future<bool> replaceMirror(String owner, Tables tables) => transaction(
    () async {
      final before = {
        for (final r in await customSelect(
          'SELECT source, rows FROM mirror WHERE owner = ?',
          variables: [Variable(owner)],
        ).get())
          r.read<String>('source'): r.read<String>('rows'),
      };
      await customUpdate(
        'DELETE FROM mirror WHERE owner = ?',
        variables: [Variable(owner)],
      );
      var changed = before.length != tables.length;
      for (final MapEntry(:key, :value) in tables.entries) {
        final rows = jsonEncode(value);
        changed |= before[key] != rows;
        await customInsert(
          'INSERT INTO mirror (owner, source, rows) VALUES (?, ?, ?)',
          variables: [Variable(owner), Variable(key), Variable(rows)],
        );
      }
      final applied = await customUpdate(
        "DELETE FROM pending_mutations WHERE owner = ? AND status = 'applied'",
        variables: [Variable(owner)],
      );
      return changed || applied > 0;
    },
  );

  /// Deletes every row that is not [owner]'s, or every row when [owner]
  /// is null (signed out).
  Future<void> keepOnly(String? owner) => transaction(() async {
    for (final table in ['mirror', 'pending_mutations', 'local_ids']) {
      await customUpdate(
        'DELETE FROM $table WHERE owner IS NOT ?',
        variables: [Variable(owner)],
      );
    }
  });
}
