/// Entorno de la build. Vacío en local. `staging` en GitHub Pages.
class AppEnv {
  const AppEnv._();

  static const name = String.fromEnvironment('APP_ENV', defaultValue: '');

  static bool get isStaging => name == 'staging';
}
