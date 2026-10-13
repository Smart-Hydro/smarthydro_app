/// Configuración de la Web App N1.
///
/// La URL `/exec` es el endpoint público de la Web App (no es un secreto).
/// Override en build/run:
/// `flutter run --dart-define=N1_WEB_APP_URL=https://script.google.com/macros/s/…/exec`
class N1Config {
  const N1Config({required this.webAppUrl});

  /// Despliegue prod verificado (doGet → ok, version 2026-10-12-flutter-app).
  static const String defaultProdWebAppUrl =
      'https://script.google.com/macros/s/AKfycbweqRfMhbH7jJzIDsQaTx_MXFgZBwkI_SIL3SENjwndBo9pkq6XOwfgXGLJvQH0Gd8/exec';

  /// Base URL de la Web App N1 (doGet/doPost). Vacía = no configurada.
  final String webAppUrl;

  bool get isConfigured => webAppUrl.trim().isNotEmpty;

  /// Lee la URL desde `--dart-define=N1_WEB_APP_URL=…`.
  /// Si no se pasa, usa [defaultProdWebAppUrl].
  factory N1Config.fromEnvironment() {
    const raw = String.fromEnvironment(
      'N1_WEB_APP_URL',
      defaultValue: defaultProdWebAppUrl,
    );
    return N1Config(webAppUrl: raw.trim());
  }
}
