import 'package:settlo_core/settlo_core.dart';

/// The auth guard. Signed out, only Welcome, its sign-in steps and invite
/// links are reachable; everything else goes to Welcome. Signed in, the
/// sign-in screens and Splash go to Home. Returns null to stay on [location].
String? authRedirect({required bool signedIn, required String location}) {
  final isSignIn = SettloRoutes.signedOut.contains(location);
  if (signedIn) {
    return isSignIn || location == SettloRoutes.splash
        ? SettloRoutes.home
        : null;
  }
  return isSignIn || location.startsWith('/join/')
      ? null
      : SettloRoutes.welcome;
}
