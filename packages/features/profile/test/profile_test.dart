import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:settlo_core/settlo_core.dart';
import 'package:settlo_core/supabase/reminders.dart';
import 'package:settlo_platform/settlo_platform.dart';
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
  int signOuts = 0;
  bool get signedOut => signOuts > 0;
  int deletions = 0;
  Object? deleteError;

  /// Sync stops and resumes, and deletion attempts, in order.
  final log = <String>[];
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
    signOuts++;
  }

  @override
  Future<void> deleteAccount() async {
    log.add('delete');
    if (deleteError case final error?) _throw(error);
    deletions++;
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
      overrides: [
        remindersEnabledProvider.overrideWith((ref) async => true),
        themeModeRepositoryProvider.overrideWithValue(repository),
      ],
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
      overrides: [
        remindersEnabledProvider.overrideWith((ref) async => true),
        sessionProvider.overrideWith(() => _SessionNotifier(null)),
      ],
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
        remindersEnabledProvider.overrideWith((ref) async => true),
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
      overrides: [
        remindersEnabledProvider.overrideWith((ref) async => true),
        profileRepositoryProvider.overrideWithValue(repository),
      ],
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
    await container.read(profileProvider.notifier).deleteAccount();
    expect(repository.deletions, 1);
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

  testWidgets('Help and support opens the existing support page', (
    tester,
  ) async {
    final opened = <Uri>[];
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          remindersEnabledProvider.overrideWith((ref) async => true),
          profileRepositoryProvider.overrideWithValue(_ProfileRepository()),
          themeModeRepositoryProvider.overrideWithValue(
            _ThemeRepository(ThemeMode.dark),
          ),
          openUrlProvider.overrideWithValue((uri) async {
            opened.add(uri);
            return true;
          }),
        ],
        child: MaterialApp(
          theme: SettloTheme.dark(),
          home: const ProfileScreen(),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(
      find.text('Help and support'),
      250,
      scrollable: find.byType(Scrollable),
    );
    await tester.tap(find.text('Help and support'));
    await tester.pump();

    expect(opened, [Uri.parse('https://settlo.hellojosh.studio/support/')]);
  });

  for (final failure in ['returns false', 'throws']) {
    testWidgets('support $failure shows safe feedback', (tester) async {
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            remindersEnabledProvider.overrideWith((ref) async => true),
            profileRepositoryProvider.overrideWithValue(_ProfileRepository()),
            themeModeRepositoryProvider.overrideWithValue(
              _ThemeRepository(ThemeMode.dark),
            ),
            openUrlProvider.overrideWithValue((_) async {
              if (failure == 'throws') throw Exception('private');
              return false;
            }),
          ],
          child: MaterialApp(
            theme: SettloTheme.dark(),
            home: const ProfileScreen(),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.scrollUntilVisible(
        find.text('Help and support'),
        250,
        scrollable: find.byType(Scrollable),
      );
      await tester.tap(find.text('Help and support'));
      await tester.pump();

      expect(find.text("We couldn't open support. Try again."), findsOne);
      expect(find.textContaining('private'), findsNothing);
    });
  }

  testWidgets('edits profile, validates VPA, and signs out', (tester) async {
    final profile = _ProfileRepository();
    final theme = _ThemeRepository(ThemeMode.dark);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          remindersEnabledProvider.overrideWith((ref) async => true),
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
    expect(tester.getSize(find.byTooltip('Close')), const Size(44, 44));
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

    await tester.drag(find.byType(CustomScrollView), const Offset(0, -700));
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

    await tester.ensureVisible(find.text('Name and UPI ID'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Name and UPI ID'));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('profile-name')), findsOneWidget);
    final nameField = find.byKey(const ValueKey('profile-name'));
    final nameLabel = find.descendant(
      of: nameField,
      matching: find.text('Name'),
    );
    final typedName = find.descendant(
      of: nameField,
      matching: find.byType(EditableText),
    );
    expect(
      tester.getRect(nameLabel).overlaps(tester.getRect(typedName)),
      isFalse,
      reason: 'the settled floating label must not cover the typed name',
    );
    await tester.tapAt(const Offset(10, 10));
    await tester.pumpAndSettle();

    await tester.ensureVisible(find.text('Sign out'));
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
          remindersEnabledProvider.overrideWith((ref) async => true),
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
    await tester.drag(find.byType(CustomScrollView), const Offset(0, -700));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('Sign out'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Sign out'));
    await tester.pumpAndSettle();
    expect(find.text("We couldn't sign you out. Try again."), findsOneWidget);
  });

  group('signing out with unsent changes', () {
    late _ProfileRepository profile;
    late int drains;

    Future<void> open(
      WidgetTester tester, {
      required int count,
      TargetPlatform platform = TargetPlatform.android,
    }) async {
      profile = _ProfileRepository();
      drains = 0;
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            remindersEnabledProvider.overrideWith((ref) async => true),
            profileRepositoryProvider.overrideWithValue(profile),
            themeModeRepositoryProvider.overrideWithValue(
              _ThemeRepository(ThemeMode.system),
            ),
            unsentChangesProvider.overrideWithValue((
              count: () async => count,
              drain: () async {
                drains++;
                // A drain that fails must not surface anywhere.
                throw StateError('offline');
              },
              stop: () async => profile.log.add('stop'),
              resume: () => profile.log.add('resume'),
            )),
          ],
          child: MaterialApp(
            theme: SettloTheme.dark().copyWith(platform: platform),
            home: const ProfileScreen(),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.drag(find.byType(CustomScrollView), const Offset(0, -700));
      await tester.pumpAndSettle();
    }

    Future<void> tapRow(WidgetTester tester, String row) async {
      await tester.ensureVisible(find.text(row));
      await tester.pumpAndSettle();
      await tester.tap(find.text(row));
      await tester.pumpAndSettle();
    }

    testWidgets('on iOS, sign out asks with an action sheet', (tester) async {
      await open(tester, count: 2, platform: TargetPlatform.iOS);
      await tapRow(tester, 'Sign out');
      expect(find.byType(CupertinoActionSheet), findsOneWidget);
      expect(find.text('You have 2 unsent changes'), findsOneWidget);

      await tester.tap(find.text('Keep'));
      await tester.pumpAndSettle();
      expect(drains, 1, reason: 'Keep sends them now');
      expect(profile.signedOut, isFalse);

      await tapRow(tester, 'Sign out');
      await tester.tap(find.text('Sign Out Anyway'));
      await tester.tap(find.text('Sign Out Anyway'), warnIfMissed: false);
      await tester.pumpAndSettle();
      expect(profile.signOuts, 1);
      expect(find.byType(ProfileScreen), findsOneWidget, reason: 'one pop');
    });

    testWidgets('on iOS, delete account asks with an alert', (tester) async {
      await open(tester, count: 0, platform: TargetPlatform.iOS);
      await tapRow(tester, 'Delete account');
      expect(find.byType(CupertinoAlertDialog), findsOneWidget);
      expect(find.text('Delete your account?'), findsOneWidget);

      await tester.tap(find.text('Keep My Account'));
      await tester.pumpAndSettle();
      expect(profile.deletions, 0);

      await tapRow(tester, 'Delete account');
      await tester.tap(find.text('Delete Account'));
      await tester.tap(find.text('Delete Account'), warnIfMissed: false);
      await tester.pumpAndSettle();
      expect(profile.deletions, 1);
      expect(find.byType(ProfileScreen), findsOneWidget, reason: 'one pop');
    });

    testWidgets('nothing unsent signs out without asking', (tester) async {
      await open(tester, count: 0);
      await tester.ensureVisible(find.text('Sign out'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Sign out'));
      await tester.pumpAndSettle();
      expect(find.text('Keep'), findsNothing);
      expect(profile.signedOut, isTrue);
    });

    testWidgets('Keep stays signed in and tries to send them', (tester) async {
      await open(tester, count: 2);
      // A double tap on the row opens one sheet.
      await tester.ensureVisible(find.text('Sign out'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Sign out'));
      await tester.tap(find.text('Sign out'), warnIfMissed: false);
      await tester.pumpAndSettle();
      expect(find.text('You have 2 unsent changes'), findsOneWidget);
      expect(profile.signedOut, isFalse);

      // No pump between the taps: one pop, one drain.
      await tester.tap(find.text('Keep'));
      await tester.tap(find.text('Keep'), warnIfMissed: false);
      await tester.pumpAndSettle();

      expect(drains, 1);
      expect(profile.signedOut, isFalse);
      expect(find.text('Keep'), findsNothing);
      expect(
        find.byType(ProfileScreen),
        findsOneWidget,
        reason: 'one pop: Profile stays under the sheet',
      );

      // The row works again afterwards.
      await tester.ensureVisible(find.text('Sign out'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Sign out'));
      await tester.pumpAndSettle();
      expect(find.text('You have 2 unsent changes'), findsOneWidget);
    });

    testWidgets('Sign out anyway signs out once on a no-pump double tap', (
      tester,
    ) async {
      await open(tester, count: 1);
      await tester.ensureVisible(find.text('Sign out'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Sign out'));
      await tester.pumpAndSettle();
      expect(find.text('You have 1 unsent change'), findsOneWidget);

      await tester.tap(find.text('Sign out anyway'));
      await tester.tap(find.text('Sign out anyway'), warnIfMissed: false);
      await tester.pumpAndSettle();

      expect(profile.signOuts, 1);
      expect(drains, 0);
      expect(find.byType(ProfileScreen), findsOneWidget);
    });

    testWidgets('dismissing the sheet stays signed in', (tester) async {
      await open(tester, count: 1);
      await tester.ensureVisible(find.text('Sign out'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Sign out'));
      await tester.pumpAndSettle();
      await tester.tapAt(const Offset(10, 10));
      await tester.pumpAndSettle();
      expect(profile.signedOut, isFalse);
      expect(drains, 0);
    });

    testWidgets('Delete account confirms, naming what goes and what stays, '
        'and deletes once on a no-pump double tap', (tester) async {
      await open(tester, count: 0);
      // A double tap on the row opens one sheet.
      await tester.ensureVisible(find.text('Delete account'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Delete account'));
      await tester.tap(find.text('Delete account'), warnIfMissed: false);
      await tester.pumpAndSettle();
      expect(find.text('Delete your account?'), findsOneWidget);
      expect(
        find.text(
          'This removes your name, UPI ID, phone number and friends list, '
          'and signs you out. Expenses, loans and settle-ups you share stay '
          "in the other people's records. This can't be undone.",
        ),
        findsOneWidget,
      );
      expect(profile.deletions, 0, reason: 'nothing before the confirmation');

      // The row is under the sheet now; these two hit the sheet's button.
      await tester.tap(find.text('Delete account').last);
      await tester.tap(find.text('Delete account').last, warnIfMissed: false);
      await tester.pumpAndSettle();

      expect(profile.deletions, 1);
      expect(profile.log, [
        'stop',
        'delete',
      ], reason: 'syncing stops before the server is asked, and stays stopped');
      expect(profile.signOuts, 0, reason: 'the repository drops the session');
      expect(find.byType(ProfileScreen), findsOneWidget);
    });

    testWidgets('Keep my account and dismissing delete nothing', (
      tester,
    ) async {
      await open(tester, count: 0);
      await tester.ensureVisible(find.text('Delete account'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Delete account'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Keep my account'));
      await tester.tap(find.text('Keep my account'), warnIfMissed: false);
      await tester.pumpAndSettle();
      expect(find.text('Delete your account?'), findsNothing);
      expect(find.byType(ProfileScreen), findsOneWidget);

      await tester.ensureVisible(find.text('Delete account'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Delete account'));
      await tester.pumpAndSettle();
      await tester.tapAt(const Offset(10, 10));
      await tester.pumpAndSettle();
      expect(profile.deletions, 0);
      expect(drains, 0);
    });

    testWidgets('Delete account warns that unsent changes are lost', (
      tester,
    ) async {
      await open(tester, count: 2);
      await tester.ensureVisible(find.text('Delete account'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Delete account'));
      await tester.pumpAndSettle();
      expect(
        find.textContaining('Your 2 unsent changes will be lost.'),
        findsOneWidget,
      );
      await tester.tap(find.text('Delete account').last);
      await tester.pumpAndSettle();
      expect(profile.deletions, 1);
    });

    testWidgets('a failed deletion uses safe copy and can be retried', (
      tester,
    ) async {
      await open(tester, count: 0);
      profile.deleteError = StateError('private');
      await tester.ensureVisible(find.text('Delete account'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Delete account'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Delete account').last);
      await tester.pumpAndSettle();
      expect(
        find.text("We couldn't delete your account. Try again."),
        findsOneWidget,
      );
      expect(find.textContaining('private'), findsNothing);
      expect(profile.log, [
        'stop',
        'delete',
        'resume',
      ], reason: 'the account stays, so syncing starts again');

      profile.deleteError = null;
      await tester.ensureVisible(find.text('Delete account'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Delete account'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Delete account').last);
      await tester.pumpAndSettle();
      expect(profile.deletions, 1);
    });
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
          remindersEnabledProvider.overrideWith((ref) async => true),
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
    await tester.drag(find.byType(CustomScrollView), const Offset(0, -700));
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

  testWidgets('no name shows a prompt, and unbuilt rows are hidden (#174)', (
    tester,
  ) async {
    final profile = _ProfileRepository()
      ..data = const ProfileData(name: '', phone: '+919000001102', upiId: null);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          remindersEnabledProvider.overrideWith((ref) async => true),
          profileRepositoryProvider.overrideWithValue(profile),
          themeModeRepositoryProvider.overrideWithValue(
            _ThemeRepository(ThemeMode.dark),
          ),
        ],
        child: MaterialApp(
          theme: SettloTheme.dark(),
          home: const ProfileScreen(),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Add your name'), findsOneWidget);
    for (final dead in ['Contacts matching', 'App lock', 'Change number']) {
      expect(find.text(dead, skipOffstage: false), findsNothing);
    }
    for (final live in ['Export', 'Appearance', 'Sign out']) {
      expect(find.text(live, skipOffstage: false), findsOneWidget);
    }
  });

  testWidgets('Export shares a space as CSV and PDF, once on a no-pump '
      'double tap', (tester) async {
    final shared = <List<(SharedFile, List<int>)>>[];
    final exports = _exportsDir();
    final sharing = Completer<void>();
    final sheet = Completer<void>();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          remindersEnabledProvider.overrideWith((ref) async => true),
          profileRepositoryProvider.overrideWithValue(_ProfileRepository()),
          themeModeRepositoryProvider.overrideWithValue(
            _ThemeRepository(ThemeMode.dark),
          ),
          spacesRepositoryProvider.overrideWithValue(_SpacesRepository()),
          spaceLedgerRepositoryProvider.overrideWithValue(_LedgerRepository()),
          shareFilesProvider.overrideWithValue((files, _) async {
            shared.add([
              for (final f in files) (f, File(f.path).readAsBytesSync()),
            ]);
            sharing.complete();
            await sheet.future;
          }),
          exportsDirectoryProvider.overrideWithValue(() async => exports),
        ],
        child: MaterialApp(
          theme: SettloTheme.dark(),
          home: const ProfileScreen(),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('Export'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Export'));
    await tester.pumpAndSettle();
    expect(find.text('CSV and PDF'), findsOneWidget);

    await tester.tap(find.text('Flat 4B'));
    await tester.tap(find.text('Flat 4B'));
    // Real file and isolate work, with pumps so its callbacks land.
    while (!sharing.isCompleted) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 20)),
      );
      await tester.pump();
    }
    await tester.pump();
    expect(find.text('Preparing…'), findsOneWidget);
    sheet.complete();
    // Its folder is deleted with real file work once the sheet closes.
    while (find.text('Preparing…').evaluate().isNotEmpty) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 20)),
      );
      await tester.pump();
    }
    await tester.pumpAndSettle();

    expect(shared, hasLength(1));
    final [(csv, csvBytes), (pdf, pdfBytes)] = shared.single;
    expect(
      csv.path,
      matches(
        RegExp(r'/exports/share-[^/]+/settlo-flat-4b-expenses-[\d-]{10}\.csv$'),
      ),
    );
    expect(csv.mimeType, 'text/csv');
    final text = utf8.decode(csvBytes);
    expect(text, contains('Rent,,no,,1000,10.00,Satheesh,1000,10.00,500,5.00'));
    expect(text, contains('Member 2,0,0.00,500,5.00'));
    expect(text, isNot(contains('98765')));
    expect(
      pdf.path,
      matches(
        RegExp(r'/exports/share-[^/]+/settlo-flat-4b-summary-[\d-]{10}\.pdf$'),
      ),
    );
    expect(String.fromCharCodes(pdfBytes.take(5)), '%PDF-');
    expect(find.text('CSV and PDF'), findsOneWidget);
  });

  testWidgets('Export says when there is nothing to export or it fails', (
    tester,
  ) async {
    final exports = _exportsDir();
    Future<void> open({bool none = false, bool fail = false}) async {
      await tester.pumpWidget(
        ProviderScope(
          key: UniqueKey(),
          overrides: [
            remindersEnabledProvider.overrideWith((ref) async => true),
            profileRepositoryProvider.overrideWithValue(_ProfileRepository()),
            themeModeRepositoryProvider.overrideWithValue(
              _ThemeRepository(ThemeMode.dark),
            ),
            spacesRepositoryProvider.overrideWithValue(
              _SpacesRepository(none: none),
            ),
            spaceLedgerRepositoryProvider.overrideWithValue(
              _LedgerRepository(fail: fail),
            ),
            shareFilesProvider.overrideWithValue((_, _) async {}),
            exportsDirectoryProvider.overrideWithValue(() async => exports),
          ],
          child: MaterialApp(
            theme: SettloTheme.dark(),
            home: const ProfileScreen(),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('Export'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Export'));
      await tester.pumpAndSettle();
    }

    await open(none: true);
    expect(find.text('No spaces to export yet.'), findsOneWidget);

    await open(fail: true);
    await tester.tap(find.text('Flat 4B'));
    await tester.pumpAndSettle();
    expect(
      find.text("We couldn't make the export. Try again."),
      findsOneWidget,
    );
    expect(find.text('CSV and PDF'), findsOneWidget);
  });
}

/// A private exports folder in a temporary directory.
Directory _exportsDir() {
  final temp = Directory.systemTemp.createTempSync('settlo');
  addTearDown(() => temp.deleteSync(recursive: true));
  return Directory('${temp.path}/exports');
}

final class _SpacesRepository implements SpacesRepository {
  new({this.none = false});

  /// Whether you have no spaces.
  final bool none;

  @override
  Future<List<SpaceSummary>> load() async => none
      ? const []
      : const [
          SpaceSummary(
            id: 's1',
            name: 'Flat 4B',
            kind: SpaceKind.flat,
            members: [
              SpaceMember(
                id: 'm1',
                name: 'Satheesh',
                phone: '+919876543210',
                isYou: true,
              ),
              SpaceMember(
                id: 'm2',
                name: '+919876543211',
                phone: '+919876543211',
              ),
            ],
          ),
        ];

  @override
  Future<String> create({
    required String name,
    required SpaceKind kind,
    required List<NewSpaceMember> members,
    required String idempotencyKey,
  }) => throw UnimplementedError();
}

final class _LedgerRepository implements SpaceLedgerRepository {
  new({this.fail = false});

  /// Whether loading fails, as when offline with nothing mirrored.
  final bool fail;

  @override
  Future<SpaceLedger> load(String spaceId) async => fail
      ? throw StateError('private')
      : SpaceLedger(
          today: DateTime(2026, 11, 10),
          expenses: [
            SpaceExpense(
              id: 'e1',
              description: 'Rent',
              amount: const Paise(1000),
              spentOn: DateTime(2026, 11),
              payers: const [(memberId: 'm1', amount: Paise(1000))],
              splits: const [
                (
                  memberId: 'm1',
                  amount: Paise(500),
                  percentBp: null,
                  shares: null,
                ),
                (
                  memberId: 'm2',
                  amount: Paise(500),
                  percentBp: null,
                  shares: null,
                ),
              ],
            ),
          ],
        );

  @override
  dynamic noSuchMethod(Invocation invocation) => throw UnimplementedError();
}
