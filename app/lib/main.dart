import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:settlo/router/router.dart';
import 'package:settlo_core/settlo_core.dart';
import 'package:settlo_profile/settlo_profile.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final config = SupabaseConfig.fromEnvironment();
  await Supabase.initialize(url: config.url, publishableKey: config.anonKey);
  runApp(const ProviderScope(child: SettloApp()));
}

/// Root widget: the router, auth guard and persisted appearance preference.
class SettloApp extends ConsumerWidget {
  /// Creates the root widget.
  const new({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) => MaterialApp.router(
    title: 'Settlo',
    debugShowCheckedModeBanner: false,
    theme: SettloTheme.light(),
    darkTheme: SettloTheme.dark(),
    themeMode: ref.watch(themeModeProvider).value ?? ThemeMode.system,
    routerConfig: ref.watch(routerProvider),
  );
}
