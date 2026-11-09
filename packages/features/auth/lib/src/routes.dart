import 'package:go_router/go_router.dart';
import 'package:settlo_auth/src/screens.dart';
import 'package:settlo_core/settlo_core.dart';

/// Splash, the sign-in steps and the invite link, all full screen.
final List<RouteBase> authRoutes = [
  GoRoute(path: SettloRoutes.splash, builder: (_, _) => const SplashScreen()),
  GoRoute(
    path: SettloRoutes.welcome,
    builder: (_, _) => const WelcomeScreen(),
    routes: [
      GoRoute(
        path: 'phone',
        builder: (_, _) => const PhoneScreen(),
        routes: [GoRoute(path: 'otp', builder: (_, _) => const OtpScreen())],
      ),
    ],
  ),
  GoRoute(
    path: SettloRoutes.joinPattern,
    builder: (_, state) => JoinScreen(token: state.pathParameters['token']!),
  ),
];
