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
