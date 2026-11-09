import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

void main() => runApp(const ProviderScope(child: SettloApp()));

final _router = GoRouter(
  routes: [GoRoute(path: '/', builder: (_, _) => const SizedBox.shrink())],
);

/// Root widget. Screens and theme arrive with their feature issues.
class SettloApp extends StatelessWidget {
  /// Creates the root widget.
  const new({super.key});

  @override
  Widget build(BuildContext context) =>
      MaterialApp.router(title: 'Settlo', routerConfig: _router);
}
