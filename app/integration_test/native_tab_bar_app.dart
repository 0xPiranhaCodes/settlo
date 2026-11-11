// The app `ios/RunnerUITests` drives with real UIKit touches (#174). From
// app/: flutter build ios --simulator --debug -t
// integration_test/native_tab_bar_app.dart, then run RunnerUITests.
//
// The fakes' signed-in Home, with the rc7 owner's profile: no name and no
// UPI ID.
import 'package:flutter/widgets.dart';
import 'package:settlo_profile/settlo_profile.dart';

import '../test/support/fake_home.dart';
import '../test/support/fake_profile.dart';
import '../test/support/fake_session.dart';

void main() => runApp(
  fakeSessionApp(
    fakeSession,
    home: FakeHomeRepository(homeMain),
    profileRepository: FakeProfileRepository(
      const ProfileData(name: '', phone: '+919000001102', upiId: null),
    ),
  ),
);
