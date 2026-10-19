/// Entorno de la build. Vacío en local.
class AppEnv {
  const AppEnv._();

  static const name = String.fromEnvironment('APP_ENV', defaultValue: '');

  static bool get isStaging => name == 'staging';

  static bool get isProduction => name == 'production';
}
