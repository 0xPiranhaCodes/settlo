import 'package:flutter/widgets.dart';
import 'package:settlo_core/settlo_core.dart';

/// Placeholder for the Splash artboard.
class SplashScreen extends StatelessWidget {
  /// The Splash screen.
  const new({super.key});

  @override
  Widget build(BuildContext context) =>
      const SPlaceholderScreen(title: 'Splash', artboard: 'Splash');
}

/// Placeholder for the Welcome artboard.
class WelcomeScreen extends StatelessWidget {
  /// The Welcome screen.
  const new({super.key});

  @override
  Widget build(BuildContext context) =>
      const SPlaceholderScreen(title: 'Welcome', artboard: 'Welcome');
}

/// Placeholder for the Phone artboard.
class PhoneScreen extends StatelessWidget {
  /// The Phone screen.
  const new({super.key});

  @override
  Widget build(BuildContext context) =>
      const SPlaceholderScreen(title: 'Phone number', artboard: 'Phone');
}

/// Placeholder for the Onboarding artboard.
class OtpScreen extends StatelessWidget {
  /// The Onboarding screen.
  const new({super.key});

  @override
  Widget build(BuildContext context) => const SPlaceholderScreen(
    title: 'Verify your number',
    artboard: 'Onboarding',
  );
}

/// Placeholder for the Join artboard.
class JoinScreen extends StatelessWidget {
  /// The Join screen for [token].
  const new({required this.token, super.key});

  /// The invite token from the link.
  final String token;

  @override
  Widget build(BuildContext context) =>
      const SPlaceholderScreen(title: 'Join', artboard: 'Join');
}
