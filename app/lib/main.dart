import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:settlo/router/router.dart';
import 'package:settlo_activity/settlo_activity.dart';
import 'package:settlo_auth/settlo_auth.dart';
import 'package:settlo_core/settlo_core.dart';
import 'package:settlo_local/settlo_local.dart';
import 'package:settlo_platform/settlo_platform.dart';
import 'package:settlo_profile/settlo_profile.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final config = SupabaseConfig.fromEnvironment();
  await Supabase.initialize(url: config.url, publishableKey: config.anonKey);
  final flat = flatChromeProvider.overrideWithValue(await prefersFlatChrome());
  runApp(
    ProviderScope(
      overrides: [...offlineRepositories, flat],
      child: const _SyncNotices(child: SettloApp()),
    ),
  );
}

final _messenger = GlobalKey<ScaffoldMessengerState>();

/// Shows each write the server refused after its sheet closed (ADR 0004),
/// and keeps the signed-in user's sync running.
class _SyncNotices extends ConsumerWidget {
  const new({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    ref.listen(syncNoticesProvider, (_, next) {
      if (next case AsyncData(:final value)) {
        _messenger.currentState?.showSnackBar(SnackBar(content: Text(value)));
      }
    });
    return child;
  }
}

/// Root widget: the router, auth guard and persisted appearance preference.
class SettloApp extends ConsumerWidget {
  /// Creates the root widget.
  const new({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Keeps the Live Activity / ongoing notification in step with the app.
    ref
      ..watch(liveActivitySyncProvider)
      ..listen(inviteSignInNoticeProvider, (_, next) {
        if (next == null) return;
        WidgetsBinding.instance.addPostFrameCallback((_) {
          _messenger.currentState?.showSnackBar(
            SnackBar(content: Text(next.message)),
          );
        });
      });
    return MaterialApp.router(
      title: 'Settlo',
      debugShowCheckedModeBanner: false,
      scaffoldMessengerKey: _messenger,
      theme: SettloTheme.light(),
      darkTheme: SettloTheme.dark(),
      themeMode: ref.watch(themeModeProvider).value ?? ThemeMode.dark,
      routerConfig: ref.watch(routerProvider),
    );
  }
}
