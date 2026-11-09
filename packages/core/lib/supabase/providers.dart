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
