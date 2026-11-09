import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:settlo_core/settlo_core.dart';
import 'package:settlo_profile/settlo_profile.dart';
import 'package:settlo_profile/src/glyphs.dart';
import 'package:shared_preferences_platform_interface/in_memory_shared_preferences_async.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_async_platform_interface.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

const _profile = ProfileData(
  name: 'Satheesh',
  phone: '+919876543210',
  upiId: 'satheesh@okaxis',
);

final class _ProfileRepository implements ProfileRepository {
  ProfileData data = _profile;
  ({String name, String? upiId})? saved;
  bool signedOut = false;
  Object? loadError;
  Object? updateError;
  Object? signOutError;

  @override
  Future<ProfileData> load() async {
    if (loadError case final error?) _throw(error);
    return data;
  }

  @override
  Future<void> signOut() async {
    if (signOutError case final error?) _throw(error);
    signedOut = true;
  }

  @override
  Future<void> update({required String name, required String? upiId}) async {
    if (updateError case final error?) _throw(error);
    saved = (name: name, upiId: upiId);
    data = ProfileData(name: name, phone: data.phone, upiId: upiId);
  }
}

Never _throw(Object error) => switch (error) {
  final Error value => throw value,
  final Exception value => throw value,
  _ => throw StateError('$error'),
};

final class _ThemeRepository implements ThemeModeRepository {
  new(this.saved);

  ThemeMode saved;
  Object? saveError;

  @override
  Future<ThemeMode> load() async => saved;

  @override
  Future<void> save(ThemeMode mode) async {
    if (saveError case final error?) _throw(error);
    saved = mode;
  }
}

final class _SessionNotifier extends SessionNotifier {
  new(this.initial);

  final Session? initial;

  @override
  Session? build() => initial;
}

void main() {
  group('server-matching validation', () {
    test('counts Unicode characters rather than UTF-16 code units', () {
      expect(validateProfileName(null), nameValidationMessage);
      expect(validateProfileName('  '), nameValidationMessage);
      expect(validateProfileName('a' * 101), nameValidationMessage);
      expect(validateProfileName('😀' * 100), isNull);
      expect(validateProfileName('😀' * 101), nameValidationMessage);
      expect(validateProfileName(' Asha K '), isNull);
    });

    test('accepts exactly the server VPA grammar and blank clears it', () {
      for (final valid in [
        '',
        'satheesh@okaxis',
        'A_1.name-bank@PSP',
        '${'a' * 255}@ab',
      ]) {
        expect(validateUpiId(valid), isNull, reason: valid);
      }
      for (final invalid in [
        'satheesh',
        '@okaxis',
        'name@1bank',
        'name@a',
        'name+tag@bank',
        '${'a' * 256}@bank',
      ]) {
        expect(validateUpiId(invalid), upiValidationMessage, reason: invalid);
      }
    });
  });

  test('theme selection survives a new controller', () async {
    final repository = _ThemeRepository(ThemeMode.system);
    ProviderContainer container() => ProviderContainer(
      overrides: [themeModeRepositoryProvider.overrideWithValue(repository)],
    );

    final first = container();
    await first.read(themeModeProvider.future);
    await first.read(themeModeProvider.notifier).setMode(ThemeMode.light);
    expect(first.read(themeModeProvider).value, ThemeMode.light);
    first.dispose();

    final restarted = container();
    addTearDown(restarted.dispose);
    expect(await restarted.read(themeModeProvider.future), ThemeMode.light);
  });

  test('stored theme modes load, save, and reject unknown values', () async {
    String? stored;
    final repository = SharedPreferencesThemeModeRepository(
      read: () async => stored,
      write: (value) async => stored = value,
    );
    expect(await repository.load(), ThemeMode.dark);
    await repository.save(ThemeMode.dark);
    expect(stored, 'dark');
    expect(await repository.load(), ThemeMode.dark);
    stored = 'sepia';
    expect(await repository.load(), ThemeMode.dark);
  });

  test(
    'default theme repository persists through the async platform',
    () async {
      SharedPreferencesAsyncPlatform.instance =
          InMemorySharedPreferencesAsync.empty();
      ProviderContainer container() => ProviderContainer();

      final first = container();
      expect(await first.read(themeModeProvider.future), ThemeMode.dark);
      await first.read(themeModeProvider.notifier).setMode(ThemeMode.light);
      first.dispose();

      final restarted = container();
      addTearDown(restarted.dispose);
      expect(await restarted.read(themeModeProvider.future), ThemeMode.light);
    },
  );

  test('profile repository provider binds to the signed-in user', () async {
    final signedOut = ProviderContainer(
      overrides: [sessionProvider.overrideWith(() => _SessionNotifier(null))],
    );
    addTearDown(signedOut.dispose);
    expect(
      () => signedOut.read(profileRepositoryProvider),
      throwsA(
        predicate<Object>(
          (error) =>
              error.toString().contains('Profile needs a signed-in user'),
          'wraps the missing-session StateError',
        ),
      ),
    );

    final client = SupabaseClient(
      'http://localhost',
      'anon',
      authOptions: const AuthClientOptions(autoRefreshToken: false),
    );
    addTearDown(client.dispose);
    final session = Session(
      accessToken: 'token',
      tokenType: 'bearer',
      user: const User(
        id: 'u1',
        appMetadata: {},
        userMetadata: {},
        aud: 'authenticated',
        createdAt: '2026-11-09T00:00:00Z',
      ),
    );
    final signedIn = ProviderContainer(
      overrides: [
        sessionProvider.overrideWith(() => _SessionNotifier(session)),
        supabaseClientProvider.overrideWithValue(client),
      ],
    );
    addTearDown(signedIn.dispose);
    final repository = signedIn.read(profileRepositoryProvider);
    expect(repository, isA<SupabaseProfileRepository>());
    expect((repository as SupabaseProfileRepository).userId, 'u1');
  });

  test('profile controller trims, clears, refreshes, and signs out', () async {
    final repository = _ProfileRepository();
    final container = ProviderContainer(
      overrides: [profileRepositoryProvider.overrideWithValue(repository)],
    );
    addTearDown(container.dispose);
    await container.read(profileProvider.future);

    await container
        .read(profileProvider.notifier)
        .save(name: ' Asha ', upiId: '  ');
    expect(repository.saved, (name: 'Asha', upiId: null));
    expect(container.read(ledgerRevisionProvider), 1);
    expect((await container.read(profileProvider.future)).name, 'Asha');

    await container.read(profileProvider.notifier).signOut();
    expect(repository.signedOut, isTrue);
  });

  testWidgets('every profile glyph paints without a font dependency', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Wrap(
          children: [
            for (final glyph in ProfileGlyph.values)
              ProfileIcon(glyph, color: Colors.black),
          ],
        ),
      ),
    );
    await tester.pump();
    expect(find.byType(ProfileIcon), findsNWidgets(ProfileGlyph.values.length));
  });

  testWidgets('edits profile, validates VPA, and signs out', (tester) async {
    final profile = _ProfileRepository();
    final theme = _ThemeRepository(ThemeMode.dark);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          profileRepositoryProvider.overrideWithValue(profile),
          themeModeRepositoryProvider.overrideWithValue(theme),
        ],
        child: MaterialApp(
          theme: SettloTheme.dark(),
          home: const ProfileScreen(),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Satheesh'), findsOneWidget);
    expect(find.text('+91 98765 43210'), findsOneWidget);
    expect(tester.getSize(find.byTooltip('Back')), const Size(44, 44));
    final change = find.ancestor(
      of: find.text('Change'),
      matching: find.byType(TextButton),
    );
    expect(tester.getSize(change).width, greaterThanOrEqualTo(44));
    expect(tester.getSize(change).height, greaterThanOrEqualTo(44));
    expect(
      tester
          .widget<TextButton>(change)
          .style
          ?.foregroundColor
          ?.resolve(const <WidgetState>{}),
      SettloColors.dark.action,
    );

    await tester.tap(find.text('Change'));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const ValueKey('profile-upi-id')),
      'not a vpa',
    );
    await tester.tap(find.text('Save'));
    await tester.pump();
    expect(find.text(upiValidationMessage), findsOneWidget);
    expect(profile.saved, isNull);

    await tester.enterText(
      find.byKey(const ValueKey('profile-name')),
      ' Asha K ',
    );
    await tester.enterText(
      find.byKey(const ValueKey('profile-upi-id')),
      'asha.k@okaxis',
    );
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();
    expect(profile.saved, (name: 'Asha K', upiId: 'asha.k@okaxis'));

    await tester.drag(find.byType(ListView), const Offset(0, -700));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Appearance'));
    await tester.pumpAndSettle();
    expect(find.text('Use system setting'), findsOneWidget);
    expect(find.widgetWithText(ListTile, 'Dark'), findsOneWidget);
    expect(find.text('Light'), findsOneWidget);
    final selectedCheck = find.descendant(
      of: find.widgetWithText(ListTile, 'Dark'),
      matching: find.byType(ProfileIcon),
    );
    expect(
      tester.widget<ProfileIcon>(selectedCheck).color,
      SettloColors.dark.textPrimary,
    );
    await tester.tap(find.text('Light'));
    await tester.pumpAndSettle();
    expect(theme.saved, ThemeMode.light);

    await tester.tap(find.text('Name and UPI ID'));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('profile-name')), findsOneWidget);
    await tester.tapAt(const Offset(10, 10));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Sign out'));
    await tester.pump();
    expect(profile.signedOut, isTrue);
  });

  testWidgets('load, save, and sign-out failures use safe copy', (
    tester,
  ) async {
    final profile = _ProfileRepository()..loadError = StateError('private');
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          profileRepositoryProvider.overrideWithValue(profile),
          themeModeRepositoryProvider.overrideWithValue(
            _ThemeRepository(ThemeMode.system),
          ),
        ],
        child: MaterialApp(
          theme: SettloTheme.dark(),
          home: const ProfileScreen(),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text("We couldn't load your profile."), findsOneWidget);

    profile.loadError = null;
    await tester.tap(find.text('Try again'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Change'));
    await tester.pumpAndSettle();

    profile.updateError = const ProfileInputException(upiValidationMessage);
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();
    expect(find.text(upiValidationMessage), findsOneWidget);

    profile.updateError = StateError('private');
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();
    expect(
      find.text("We couldn't save your profile. Try again."),
      findsOneWidget,
    );
    await tester.tapAt(const Offset(10, 10));
    await tester.pumpAndSettle();

    profile.signOutError = StateError('private');
    await tester.drag(find.byType(ListView), const Offset(0, -700));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Sign out'));
    await tester.pumpAndSettle();
    expect(find.text("We couldn't sign you out. Try again."), findsOneWidget);
  });

  testWidgets('appearance save failures use safe copy and keep the sheet', (
    tester,
  ) async {
    final profile = _ProfileRepository();
    final theme = _ThemeRepository(ThemeMode.dark)
      ..saveError = StateError('private');
    await tester.pumpWidget(
      ProviderScope(
        key: UniqueKey(),
        overrides: [
          profileRepositoryProvider.overrideWithValue(profile),
          themeModeRepositoryProvider.overrideWithValue(theme),
        ],
        child: MaterialApp(
          theme: SettloTheme.dark(),
          home: const ProfileScreen(),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.drag(find.byType(ListView), const Offset(0, -700));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Appearance'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Light'));
    await tester.pump();
    await tester.pump();
    expect(
      find.text("We couldn't change your appearance. Try again."),
      findsOneWidget,
    );
    expect(find.text('Appearance'), findsNWidgets(2));
    expect(theme.saved, ThemeMode.dark);
  });
}
