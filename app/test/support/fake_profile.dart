import 'package:flutter/material.dart';
import 'package:settlo_profile/settlo_profile.dart';

/// Stable profile used by app tests and goldens.
const fakeProfile = ProfileData(
  name: 'Satheesh',
  phone: '+919876543210',
  upiId: 'satheesh@okaxis',
);

/// In-memory profile repository for app composition tests.
final class FakeProfileRepository implements ProfileRepository {
  /// Starts with [data].
  new([this.data = fakeProfile]);

  /// Current profile.
  ProfileData data;

  @override
  Future<ProfileData> load() async => data;

  @override
  Future<void> signOut() async {}

  @override
  Future<void> update({required String name, required String? upiId}) async {
    data = ProfileData(name: name, phone: data.phone, upiId: upiId);
  }
}

/// In-memory appearance preference for app tests.
final class FakeThemeModeRepository implements ThemeModeRepository {
  /// Starts with [mode].
  new([this.mode = ThemeMode.dark]);

  /// Current setting.
  ThemeMode mode;

  @override
  Future<ThemeMode> load() async => mode;

  @override
  Future<void> save(ThemeMode mode) async => this.mode = mode;
}
