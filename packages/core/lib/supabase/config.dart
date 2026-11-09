/// Supabase connection settings, compiled in with
/// `--dart-define-from-file=.env.json` (template: `app/.env.example.json`).
/// Never hard-coded.
final class SupabaseConfig {
  /// Settings with [url] and [anonKey].
  const new({required this.url, required this.anonKey});

  /// Reads `SUPABASE_URL` and `SUPABASE_ANON_KEY` from the compile-time
  /// environment. Throws a [StateError] naming the missing keys.
  factory fromEnvironment() => SupabaseConfig.from(
    url: const String.fromEnvironment('SUPABASE_URL'),
    anonKey: const String.fromEnvironment('SUPABASE_ANON_KEY'),
  );

  /// Validates [url] and [anonKey]; an empty value throws a [StateError].
  factory from({required String url, required String anonKey}) {
    final missing = [
      if (url.isEmpty) 'SUPABASE_URL',
      if (anonKey.isEmpty) 'SUPABASE_ANON_KEY',
    ];
    if (missing.isNotEmpty) {
      throw StateError(
        '${missing.join(' and ')} not set. Run with '
        '--dart-define-from-file=.env.json (see app/.env.example.json).',
      );
    }
    return SupabaseConfig(url: url, anonKey: anonKey);
  }

  /// The project's API URL.
  final String url;

  /// The project's anon (publishable) key. Safe to ship; RLS guards data.
  final String anonKey;
}
