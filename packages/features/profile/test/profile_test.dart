import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:settlo_core/settlo_core.dart';
import 'package:settlo_profile/settlo_profile.dart';

const _profile = ProfileData(
  name: 'Satheesh',
  phone: '+919876543210',
  upiId: 'satheesh@okaxis',
);

final class _ProfileRepository implements ProfileRepository {
  ProfileData data = _profile;
  ({String name, String? upiId})? saved;
  bool signedOut = false;

  @override
  Future<ProfileData> load() async => data;

  @override
  Future<void> signOut() async => signedOut = true;

  @override
  Future<void> update({required String name, required String? upiId}) async {
    saved = (name: name, upiId: upiId);
    data = ProfileData(name: name, phone: data.phone, upiId: upiId);
  }
}

final class _ThemeRepository implements ThemeModeRepository {
  new(this.saved);

  ThemeMode saved;

  @override
  Future<ThemeMode> load() async => saved;

  @override
  Future<void> save(ThemeMode mode) async => saved = mode;
}

void main() {
  group('server-matching validation', () {
    test('requires a trimmed name no longer than 100 characters', () {
      expect(validateProfileName(null), nameValidationMessage);
      expect(validateProfileName('  '), nameValidationMessage);
      expect(validateProfileName('a' * 101), nameValidationMessage);
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
    await tester.tap(find.text('Sign out'));
    await tester.pump();
    expect(profile.signedOut, isTrue);
  });
}
