// Offline fixture app for the issue #202 iOS HID evidence pass.
// Build with flutter build ios --simulator --debug -t integration_test/palette_app.dart.
import 'package:flutter/material.dart';
import 'package:settlo_core/settlo_core.dart';

import '../test/support/fake_expenses.dart';
import '../test/support/fake_home.dart';
import '../test/support/fake_phone_auth.dart';
import '../test/support/fake_session.dart';

void main() => runApp(
  fakeSessionApp(
    const bool.fromEnvironment('PALETTE_AUTH') ? null : fakeSession,
    themeMode: ThemeMode.system,
    home: FakeHomeRepository(homeMain),
    overrides: [
      expensesRepositoryProvider.overrideWithValue(FakeExpensesRepository()),
      phoneAuthProvider.overrideWithValue(FakePhoneAuth()),
    ],
  ),
);
