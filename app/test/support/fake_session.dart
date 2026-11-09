import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:settlo/main.dart';
import 'package:settlo_core/settlo_core.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'fake_home.dart';
import 'fake_spaces.dart';

/// A signed-in session for a test user; no network or storage involved.
final fakeSession = Session(
  accessToken: 'test-access-token',
  tokenType: 'bearer',
  user: const User(
    id: '00000000-0000-0000-0000-000000000001',
    appMetadata: {},
    userMetadata: {},
    aud: 'authenticated',
    createdAt: '2026-11-09T00:00:00Z',
    phone: '919876543210',
  ),
);

/// Replaces [SessionNotifier] so tests choose the session and change it.
class FakeSessionNotifier extends SessionNotifier {
  /// Starts with [initial].
  new(this.initial);

  /// The session at build time.
  final Session? initial;

  @override
  Session? build() => initial;

  /// Signs in as [fakeSession], as an auth state change would.
  void signIn() => state = fakeSession;

  /// Signs out, as an auth state change would.
  void signOut() => state = null;
}

/// [SettloApp] with the session faked to [session], an empty Home and the
/// SpacesList spaces.
Widget fakeSessionApp(Session? session) => ProviderScope(
  overrides: [
    sessionProvider.overrideWith(() => FakeSessionNotifier(session)),
    homeRepositoryProvider.overrideWithValue(FakeHomeRepository(homeEmpty)),
    spacesRepositoryProvider.overrideWithValue(
      FakeSpacesRepository(spacesList),
    ),
  ],
  child: const SettloApp(),
);
