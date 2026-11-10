import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// The Supabase client. `main` initialises Supabase before the first read;
/// tests override this.
final supabaseClientProvider = Provider<SupabaseClient>(
  (ref) => Supabase.instance.client,
);

/// The signed-in session, or null when signed out. Starts from the session
/// Supabase restored from storage, so a signed-in launch never shows Welcome,
/// then follows auth state changes.
final sessionProvider = NotifierProvider<SessionNotifier, Session?>(
  SessionNotifier.new,
);

/// Holds the current [Session]; see [sessionProvider].
class SessionNotifier extends Notifier<Session?> {
  /// The current auth identity, for work that must reject stale completions.
  String? get userId => state?.user.id;

  @override
  Session? build() {
    final auth = ref.watch(supabaseClientProvider).auth;
    final subscription = auth.onAuthStateChange.listen(
      (change) => state = change.session,
    );
    ref.onDispose(subscription.cancel);
    return auth.currentSession;
  }
}

/// Bumped after a write that changes what more than one tab shows, such as
/// a new space. Screens that cache data watch it so they reload; features
/// cannot reach each other's providers (ADR 0002).
final ledgerRevisionProvider = NotifierProvider<LedgerRevision, int>(
  LedgerRevision.new,
);

/// The counter behind [ledgerRevisionProvider].
class LedgerRevision extends Notifier<int> {
  @override
  int build() => 0;

  /// Tells every watcher the ledger changed.
  void bump() => state++;
}

/// Writes made on this phone that the server has not taken yet (ADR 0004):
/// how many, and a way to try sending them now.
typedef UnsentChanges = ({
  Future<int> Function() count,
  Future<void> Function() drain,
});

/// The signed-in user's [UnsentChanges]; null when nothing queues writes,
/// as with the online repositories. `local` overrides it.
final unsentChangesProvider = Provider<UnsentChanges?>((ref) => null);
