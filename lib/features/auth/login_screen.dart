import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/api/smarthydro_api.dart';
import '../../core/session/session_provider.dart';
import '../../shared/widgets/hydro_entrance.dart';
import '../../shared/widgets/water_atmosphere.dart';

class LoginScreen extends ConsumerStatefulWidget {
  const LoginScreen({super.key});

  @override
  ConsumerState<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends ConsumerState<LoginScreen> {
  final _formKey = GlobalKey<FormState>();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  bool _obscurePassword = true;
  bool _busy = false;
  String? _loginError;

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  Future<void> _signIn() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() {
      _busy = true;
      _loginError = null;
    });
    try {
      final session = await ref
          .read(smartHydroApiProvider)
          .login(
            email: _emailController.text,
            password: _passwordController.text,
          );
      if (!mounted) return;
      ref.read(sessionProvider.notifier).signIn(session);
    } on SmartHydroApiException catch (error) {
      if (mounted) setState(() => _loginError = error.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _forgotPassword() async {
    final email = _emailController.text.trim();
    if (email.isEmpty || !email.contains('@')) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Escribe tu correo para solicitar la recuperación.'),
        ),
      );
      return;
    }
    try {
      await ref.read(smartHydroApiProvider).requestPasswordReset(email);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Si el correo está registrado, recibirás instrucciones para recuperar tu clave.',
          ),
        ),
      );
    } on SmartHydroApiException catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(error.message)));
    }
  }

  @override
  Widget build(BuildContext context) {
    final busy = _busy;

    return Scaffold(
      backgroundColor: const Color(0xFF071215),
      body: Stack(
        children: [
          const Positioned.fill(child: WaterAtmosphere(opacity: 0.35)),
          SafeArea(
            child: Center(
              child: SingleChildScrollView(
                padding: const EdgeInsets.symmetric(
                  horizontal: 28,
                  vertical: 32,
                ),
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 420),
                  child: Form(
                      key: _formKey,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          const HydroEntrance(
                            duration: Duration(milliseconds: 560),
                            child: _LoginBrand(),
                          ),
                          const SizedBox(height: 48),
                          const HydroEntrance(
                            delay: Duration(milliseconds: 80),
                            duration: Duration(milliseconds: 520),
                            child: Text(
                              'Control de Captaciones',
                              style: TextStyle(
                                fontSize: 32,
                                fontWeight: FontWeight.w900,
                                color: Color(0xFFF4FBF8),
                                letterSpacing: -0.8,
                              ),
                            ),
                          ),
                          const SizedBox(height: 10),
                          const HydroEntrance(
                            delay: Duration(milliseconds: 140),
                            child: Text(
                              'Monitoreo telemétrico de pozos y fuentes de agua en tiempo real.',
                              style: TextStyle(
                                color: Color(0xFF8FA8A8),
                                fontSize: 14,
                                height: 1.5,
                              ),
                            ),
                          ),
                          const SizedBox(height: 38),
                          HydroEntrance(
                            delay: const Duration(milliseconds: 200),
                            child: TextFormField(
                            controller: _emailController,
                            enabled: !busy,
                            keyboardType: TextInputType.emailAddress,
                            autofillHints: const [
                              AutofillHints.username,
                              AutofillHints.email,
                            ],
                            textInputAction: TextInputAction.next,
                            decoration: _inputDecoration(
                              'Correo corporativo',
                              Icons.alternate_email_rounded,
                            ),
                            validator: (value) {
                              final email = value?.trim() ?? '';
                              if (email.isEmpty || !email.contains('@')) {
                                return 'Ingresa un correo válido.';
                              }
                              return null;
                            },
                          ),
                          ),
                          const SizedBox(height: 18),
                          HydroEntrance(
                            delay: const Duration(milliseconds: 260),
                            child: TextFormField(
                            controller: _passwordController,
                            enabled: !busy,
                            obscureText: _obscurePassword,
                            autofillHints: const [AutofillHints.password],
                            textInputAction: TextInputAction.done,
                            onFieldSubmitted: (_) => _signIn(),
                            decoration:
                                _inputDecoration(
                                  'Contraseña de acceso',
                                  Icons.lock_outline_rounded,
                                ).copyWith(
                                  suffixIcon: IconButton(
                                    tooltip: _obscurePassword
                                        ? 'Mostrar contraseña'
                                        : 'Ocultar contraseña',
                                    onPressed: busy
                                        ? null
                                        : () => setState(
                                            () => _obscurePassword =
                                                !_obscurePassword,
                                          ),
                                    icon: Icon(
                                      _obscurePassword
                                          ? Icons.visibility_outlined
                                          : Icons.visibility_off_outlined,
                                      color: const Color(0xFF8FA8A8),
                                    ),
                                  ),
                                ),
                            validator: (value) => (value ?? '').isEmpty
                                ? 'Ingresa tu contraseña.'
                                : null,
                          ),
                          ),
                          const SizedBox(height: 10),
                          HydroEntrance(
                            delay: const Duration(milliseconds: 300),
                            child: Align(
                            alignment: Alignment.centerRight,
                            child: TextButton(
                              onPressed: busy ? null : _forgotPassword,
                              style: TextButton.styleFrom(
                                foregroundColor: const Color(0xFF66E0C2),
                              ),
                              child: const Text('¿Olvidaste tu contraseña?'),
                            ),
                          ),
                          ),
                          const SizedBox(height: 12),
                          AnimatedSize(
                            duration: const Duration(milliseconds: 250),
                            curve: Curves.easeOutCubic,
                            alignment: Alignment.topCenter,
                            child: _loginError == null
                                ? const SizedBox(width: double.infinity)
                                : Semantics(
                                    liveRegion: true,
                                    child: Container(
                                      width: double.infinity,
                                      margin: const EdgeInsets.only(bottom: 12),
                                      padding: const EdgeInsets.all(12),
                                      decoration: BoxDecoration(
                                        color: const Color(
                                          0xFFFF847A,
                                        ).withValues(alpha: 0.1),
                                        borderRadius: BorderRadius.circular(12),
                                        border: Border.all(
                                          color: const Color(
                                            0xFFFF847A,
                                          ).withValues(alpha: 0.25),
                                        ),
                                      ),
                                      child: Row(
                                        children: [
                                          const Icon(
                                            Icons.error_outline_rounded,
                                            size: 18,
                                            color: Color(0xFFFFA39B),
                                          ),
                                          const SizedBox(width: 8),
                                          Expanded(
                                            child: Text(
                                              _loginError!,
                                              style: const TextStyle(
                                                color: Color(0xFFFFA39B),
                                                fontSize: 13,
                                              ),
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ),
                          ),
                          HydroEntrance(
                            delay: const Duration(milliseconds: 340),
                            child: FilledButton(
                            onPressed: busy ? null : _signIn,
                            style: FilledButton.styleFrom(
                              minimumSize: const Size.fromHeight(52),
                              backgroundColor: const Color(0xFF66E0C2),
                              foregroundColor: const Color(0xFF09201F),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(15),
                              ),
                            ),
                            child: AnimatedSwitcher(
                              duration: const Duration(milliseconds: 220),
                              child: busy
                                  ? const Row(
                                      key: ValueKey('busy'),
                                      mainAxisAlignment:
                                          MainAxisAlignment.center,
                                      children: [
                                        SizedBox.square(
                                          dimension: 20,
                                          child: CircularProgressIndicator(
                                            strokeWidth: 2,
                                          ),
                                        ),
                                        SizedBox(width: 12),
                                        Text(
                                          'Conectando…',
                                          style: TextStyle(
                                            fontWeight: FontWeight.w800,
                                          ),
                                        ),
                                      ],
                                    )
                                  : const Text(
                                      'Iniciar sesión',
                                      key: ValueKey('idle'),
                                      style: TextStyle(
                                        fontWeight: FontWeight.w800,
                                      ),
                                    ),
                            ),
                          ),
                          ),
                          const SizedBox(height: 22),
                          const HydroEntrance(
                            delay: Duration(milliseconds: 380),
                            child: Text(
                              'Accede con tu cuenta actual de SmartHydro.',
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                color: Color(0xFFA9BFC0),
                                fontSize: 13,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  InputDecoration _inputDecoration(String label, IconData icon) {
    return InputDecoration(
      labelText: label,
      labelStyle: const TextStyle(color: Color(0xFF8FA8A8), fontSize: 13),
      prefixIcon: Icon(icon, color: const Color(0xFF66E0C2), size: 20),
      filled: true,
      fillColor: const Color(0xFF0C1B20).withValues(alpha: 0.7),
      contentPadding: const EdgeInsets.symmetric(horizontal: 18, vertical: 18),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(16),
        borderSide: BorderSide(color: Colors.white.withValues(alpha: 0.08)),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(16),
        borderSide: BorderSide(
          color: const Color(0xFF66E0C2).withValues(alpha: 0.15),
          width: 1,
        ),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(16),
        borderSide: const BorderSide(color: Color(0xFF66E0C2), width: 1.5),
      ),
    );
  }
}

class _LoginBrand extends StatelessWidget {
  const _LoginBrand();

  @override
  Widget build(BuildContext context) {
    return const Row(
      children: [
        DecoratedBox(
          decoration: BoxDecoration(
            color: Color(0x1F66E0C2),
            borderRadius: BorderRadius.all(Radius.circular(15)),
          ),
          child: SizedBox(
            height: 50,
            width: 50,
            child: Icon(
              Icons.water_drop_rounded,
              color: Color(0xFF66E0C2),
              size: 28,
            ),
          ),
        ),
        SizedBox(width: 13),
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'SmartHydro',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800),
            ),
            SizedBox(height: 3),
            Text(
              'CENTRO DE CONTROL',
              style: TextStyle(
                color: Color(0xFF8FA8A8),
                fontSize: 9,
                letterSpacing: 1.3,
              ),
            ),
          ],
        ),
      ],
    );
  }
}
