import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:settlo/router/router.dart';
import 'package:settlo_activity/settlo_activity.dart';
import 'package:settlo_auth/settlo_auth.dart';
import 'package:settlo_balances/settlo_balances.dart';
import 'package:settlo_core/settlo_core.dart';
import 'package:settlo_local/settlo_local.dart';
import 'package:settlo_platform/settlo_platform.dart';
import 'package:settlo_profile/settlo_profile.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // Statements from the last run must not outlive it. Awaited, so it can
  // never delete an export made after launch.
  await clearExportsAtStart();
  final config = SupabaseConfig.fromEnvironment();
  await Supabase.initialize(url: config.url, publishableKey: config.anonKey);
  final flat = flatChromeProvider.overrideWithValue(await prefersFlatChrome());
  // The tab avatars' initial comes from Home's data (#197).
  final accountName = accountNameProvider.overrideWith(
    (ref) => ref.watch(homeProvider).value?.name,
  );
  runApp(
    ProviderScope(
      overrides: [...offlineRepositories, flat, accountName],
      child: const _SyncNotices(child: SettloApp()),
    ),
  );
}

/// Shows each write the server refused after its sheet closed (ADR 0004),
/// and keeps the signed-in user's sync running.
class _SyncNotices extends ConsumerWidget {
  const new({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    ref.listen(syncNoticesProvider, (_, next) {
      if (next case AsyncData(:final value)) _notice(ref, value);
    });
    return child;
  }
}

/// Shows [message] from above every screen, through the root navigator.
void _notice(WidgetRef ref, String message) {
  final root = ref.read(routerProvider).routerDelegate.navigatorKey;
  if (root.currentContext case final context?) {
    showSettloNotice(context, message);
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
      ..watch(reminderSyncProvider)
      ..listen(inviteSignInNoticeProvider, (_, next) {
        if (next == null) return;
        WidgetsBinding.instance.addPostFrameCallback(
          (_) => _notice(ref, next.message),
        );
      });
    return MaterialApp.router(
      title: 'SabkiJeb',
      scrollBehavior: const SettloScrollBehavior(),
      debugShowCheckedModeBanner: false,
      theme: SettloTheme.light(),
      darkTheme: SettloTheme.dark(),
      themeMode: ref.watch(themeModeProvider).value ?? ThemeMode.dark,
      routerConfig: ref.watch(routerProvider),
      // A closing sheet removes its light status bar region and nothing else
      // replaces it; this one sits under every route (#259).
      builder: (context, child) => AnnotatedRegion<SystemUiOverlayStyle>(
        value: Theme.of(context).brightness == Brightness.dark
            ? const SystemUiOverlayStyle(
                statusBarBrightness: Brightness.dark,
                statusBarIconBrightness: Brightness.light,
              )
            : const SystemUiOverlayStyle(
                statusBarBrightness: Brightness.light,
                statusBarIconBrightness: Brightness.dark,
              ),
        child: child!,
      ),
    );
  }
}
