import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart';
import 'package:settlo/main.dart';
import 'package:settlo_core/settlo_core.dart';
import 'package:settlo_profile/settlo_profile.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'fake_home.dart';
import 'fake_loans.dart';
import 'fake_profile.dart';
import 'fake_space_ledger.dart';
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
/// SpacesList spaces with their ledgers, and the Loans tab's loans; [home],
/// [loans] and [overrides] replace those.
Widget fakeSessionApp(
  Session? session, {
  ThemeMode themeMode = ThemeMode.dark,
  ThemeModeRepository? themeModeRepository,
  HomeRepository? home,
  LoansRepository? loans,
  List<Override> overrides = const [],
}) => ProviderScope(
  overrides: [
    ...overrides,
    sessionProvider.overrideWith(() => FakeSessionNotifier(session)),
    homeRepositoryProvider.overrideWithValue(
      home ?? FakeHomeRepository(homeEmpty),
    ),
    spacesRepositoryProvider.overrideWithValue(
      FakeSpacesRepository(spacesList),
    ),
    spaceLedgerRepositoryProvider.overrideWithValue(
      FakeSpaceLedgerRepository(),
    ),
    loansRepositoryProvider.overrideWithValue(
      loans ?? FakeLoansRepository(loansList()),
    ),
    profileRepositoryProvider.overrideWithValue(FakeProfileRepository()),
    themeModeRepositoryProvider.overrideWithValue(
      themeModeRepository ?? FakeThemeModeRepository(themeMode),
    ),
  ],
  child: const SettloApp(),
);
