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
/// before anything syncs. Syncs on build and whenever the app resumes.
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
  ref.onDispose(() {
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

/// Swaps the interim online repositories for the mirror (#53). `app`
/// passes these to its `ProviderScope`; tests keep the online defaults or
/// fakes.
final List<Override> offlineRepositories = [
  homeRepositoryProvider.overrideWith((ref) {
    final sync = _engine(ref);
    return DriftHomeRepository(
      sync,
      SupabaseHomeRepository(
        ref.watch(supabaseClientProvider),
        userId: sync.owner,
      ),
    );
  }),
  spacesRepositoryProvider.overrideWith(
    (ref) => DriftSpacesRepository(_engine(ref)),
  ),
  expensesRepositoryProvider.overrideWith(
    (ref) => DriftExpensesRepository(_engine(ref)),
  ),
  spaceLedgerRepositoryProvider.overrideWith(
    (ref) => DriftSpaceLedgerRepository(_engine(ref)),
  ),
];
