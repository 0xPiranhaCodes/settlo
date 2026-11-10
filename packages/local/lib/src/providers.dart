import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart';
import 'package:settlo_core/settlo_core.dart';
import 'package:settlo_local/src/db.dart';
import 'package:settlo_local/src/repositories.dart';
import 'package:settlo_local/src/sync.dart';

/// The on-device database; tests override it with an in-memory one.
final localDbProvider = Provider<LocalDb>((ref) {
  final db = LocalDb.open();
  ref.onDispose(db.close);
  return db;
});

/// The signed-in user's sync engine, or null when signed out. A new user
/// (or signing out) deletes every row of anyone else, queue included,
/// before anything syncs. The last engine is disposed first, which drops
/// the request it has in flight, and the wipe starts a new session in the
/// database, so a late answer writes nothing. Syncs on build, whenever the
/// app resumes, and on every [ledgerRevisionProvider] bump, so writes still
/// made online (invites, the profile) reach the mirror; it bumps back only
/// when the mirror changed, so the two settle.
final syncEngineProvider = Provider<SyncEngine?>((ref) {
  final db = ref.watch(localDbProvider);
  final userId = ref.watch(sessionProvider.select((s) => s?.user.id));
  // Queued before the first sync's reads, so they never see another user.
  unawaited(db.keepOnly(userId));
  if (userId == null) return null;
  final engine = SyncEngine(
    db,
    ref.watch(supabaseClientProvider),
    owner: userId,
    onChanged: () => ref.read(ledgerRevisionProvider.notifier).bump(),
  );
  final lifecycle = AppLifecycleListener(
    onResume: () => unawaited(engine.sync()),
  );
  ref
    ..listen(ledgerRevisionProvider, (_, _) => unawaited(engine.sync()))
    ..onDispose(() {
      lifecycle.dispose();
      engine.dispose();
    });
  unawaited(engine.sync());
  return engine;
});

/// Refused writes to tell the user about, one sentence each.
final syncNoticesProvider = StreamProvider<String>(
  (ref) => ref.watch(syncEngineProvider)?.notices ?? const Stream.empty(),
);

SyncEngine _engine(Ref ref) =>
    ref.watch(syncEngineProvider) ??
    (throw StateError('The offline mirror needs a signed-in user'));

/// Swaps the interim online repositories for the mirror (#53, #116). `app`
/// passes these to its `ProviderScope`; tests keep the online defaults or
/// fakes.
final List<Override> offlineRepositories = [
  homeRepositoryProvider.overrideWith(
    (ref) => DriftHomeRepository(_engine(ref)),
  ),
  spacesRepositoryProvider.overrideWith(
    (ref) => DriftSpacesRepository(_engine(ref)),
  ),
  expensesRepositoryProvider.overrideWith(
    (ref) => DriftExpensesRepository(_engine(ref)),
  ),
  spaceLedgerRepositoryProvider.overrideWith(
    (ref) => DriftSpaceLedgerRepository(_engine(ref)),
  ),
  loansRepositoryProvider.overrideWith(
    (ref) => DriftLoansRepository(_engine(ref)),
  ),
  activityRepositoryProvider.overrideWith(
    (ref) => DriftActivityRepository(
      _engine(ref),
      SupabaseActivityRepository(ref.watch(supabaseClientProvider)),
    ),
  ),
  unsentChangesProvider.overrideWith((ref) {
    final sync = ref.watch(syncEngineProvider);
    if (sync == null) return null;
    return (
      count: sync.unsent,
      drain: sync.sync,
      // Keeping only the owner's rows deletes nothing of theirs; it is the
      // new session generation that makes a late answer write nothing.
      stop: () {
        sync.dispose();
        return ref.read(localDbProvider).keepOnly(sync.owner);
      },
      resume: () => ref.invalidate(syncEngineProvider),
    );
  }),
];
