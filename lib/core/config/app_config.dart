/// Central app configuration.
///
/// Supabase credentials are injected at build/run time via --dart-define, e.g.:
///
/// ```sh
/// flutter run \
///   --dart-define=SUPABASE_URL=https://xxxx.supabase.co \
///   --dart-define=SUPABASE_ANON_KEY=eyJhbGciOi...
/// ```
///
/// This keeps secrets out of the repository. See README.md for full setup.
class AppConfig {
  AppConfig._();

  static const String appName = 'Gateway Gas Enterprises';
  static const String appVersion = '0.1.0';

  static const String supabaseUrl = String.fromEnvironment(
    'SUPABASE_URL',
    defaultValue: 'https://YOUR-PROJECT-REF.supabase.co',
  );

  static const String supabaseAnonKey = String.fromEnvironment(
    'SUPABASE_ANON_KEY',
    defaultValue: 'YOUR-ANON-KEY',
  );

  static bool get hasSupabaseConfigured =>
      !supabaseUrl.contains('YOUR-PROJECT-REF') &&
      !supabaseAnonKey.contains('YOUR-ANON-KEY');
}
