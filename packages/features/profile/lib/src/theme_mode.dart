import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _themeModeKey = 'settlo.theme_mode';

/// Device storage for the user's theme choice.
abstract interface class ThemeModeRepository {
  /// Reads the saved choice; defaults to following the system.
  Future<ThemeMode> load();

  /// Persists [mode].
  Future<void> save(ThemeMode mode);
}

/// Theme settings stored in platform preferences (ADR 0008).
final class SharedPreferencesThemeModeRepository
    implements ThemeModeRepository {
  /// Uses the uncached preferences API so reads reflect durable storage.
  const new(this.preferences);

  /// Platform preferences.
  final SharedPreferencesAsync preferences;

  @override
  Future<ThemeMode> load() async {
    final saved = await preferences.getString(_themeModeKey);
    return ThemeMode.values.where((mode) => mode.name == saved).firstOrNull ??
        ThemeMode.system;
  }

  @override
  Future<void> save(ThemeMode mode) =>
      preferences.setString(_themeModeKey, mode.name);
}

/// Theme preference storage. Tests replace this with memory storage.
final themeModeRepositoryProvider = Provider<ThemeModeRepository>(
  (_) => SharedPreferencesThemeModeRepository(SharedPreferencesAsync()),
);

/// The persisted app theme.
final themeModeProvider = AsyncNotifierProvider<ThemeModeController, ThemeMode>(
  ThemeModeController.new,
);

/// Loads and persists the theme mode.
class ThemeModeController extends AsyncNotifier<ThemeMode> {
  @override
  Future<ThemeMode> build() => ref.watch(themeModeRepositoryProvider).load();

  /// Applies [mode] after it has been written successfully.
  Future<void> setMode(ThemeMode mode) async {
    await ref.read(themeModeRepositoryProvider).save(mode);
    state = AsyncData(mode);
  }
}
