/// Central app configuration.
///
/// Defaults point to the Gateway Gas dev project. Override at build/run time
/// with --dart-define, e.g.:
///
/// ```sh
/// flutter run \
///   --dart-define=SUPABASE_URL=https://xxxx.supabase.co \
///   --dart-define=SUPABASE_PUBLISHABLE_KEY=sb_publishable_xxx
/// ```
///
/// The publishable key is a *public* client-side key (security comes from
/// Row Level Security), so baking it in as a default is safe.
class AppConfig {
  AppConfig._();

  static const String appName = 'Gateway Gas Enterprises';
  static const String appVersion = '0.1.0';

  static const String _urlOverride = String.fromEnvironment('SUPABASE_URL');
  static const String _keyPublishable =
      String.fromEnvironment('SUPABASE_PUBLISHABLE_KEY');
  static const String _keyAnon = String.fromEnvironment('SUPABASE_ANON_KEY');

  static const String supabaseUrl =
      'https://vvdmuppyszaknkvnhqtg.supabase.co';

  static const String supabasePublishableKey =
      'sb_publishable_3dG8fG0ruS-jVA1q_pbznw_0RmPqRZD';

  static String get supabaseUrlEffective =>
      _urlOverride.isNotEmpty ? _urlOverride : supabaseUrl;

  static String get supabaseKeyEffective => _keyPublishable.isNotEmpty
      ? _keyPublishable
      : (_keyAnon.isNotEmpty ? _keyAnon : supabasePublishableKey);

  static bool get hasSupabaseConfigured =>
      supabaseUrlEffective.startsWith('https://') &&
      supabaseKeyEffective.isNotEmpty;
}
