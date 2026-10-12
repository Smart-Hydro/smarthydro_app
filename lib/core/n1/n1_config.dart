/// Configuración de la Web App N1 (sin secretos hardcodeados).
///
/// URL de despliegue Apps Script (`…/macros/s/…/exec`) vía:
/// `flutter run --dart-define=N1_WEB_APP_URL=https://script.google.com/macros/s/…/exec`
class N1Config {
  const N1Config({required this.webAppUrl});

  /// Base URL de la Web App N1 (doGet/doPost). Vacía = no configurada.
  final String webAppUrl;

  bool get isConfigured => webAppUrl.trim().isNotEmpty;

  /// Lee la URL desde `--dart-define=N1_WEB_APP_URL=…`.
  factory N1Config.fromEnvironment() {
    const raw = String.fromEnvironment('N1_WEB_APP_URL', defaultValue: '');
    return N1Config(webAppUrl: raw.trim());
  }
}
