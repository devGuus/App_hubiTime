/// Configuração de ambiente, injetada em tempo de build com --dart-define
/// (ou --dart-define-from-file). Só valores públicos: a chave anon é feita
/// para ser pública (a proteção real é o RLS). NUNCA colocar service_role aqui.
library;

class AppConfig {
  const AppConfig._();

  static const supabaseUrl = String.fromEnvironment('SUPABASE_URL');
  static const supabaseAnonKey = String.fromEnvironment('SUPABASE_ANON_KEY');

  /// Endereço do site do Hubi Time para o ambiente (ex.: https://meu-site.vercel.app).
  static const siteUrl = String.fromEnvironment('SITE_URL');

  static bool get isSupabaseConfigured => supabaseUrl.isNotEmpty && supabaseAnonKey.isNotEmpty;

  static Uri? get siteUri {
    final uri = Uri.tryParse(siteUrl);
    if (uri == null || !uri.hasScheme || uri.host.isEmpty) return null;
    return uri;
  }
}
