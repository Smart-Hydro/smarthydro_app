import 'package:flutter/material.dart';

import '../../core/api/smarthydro_api.dart';

class ProfileScreen extends StatefulWidget {
  const ProfileScreen({
    required this.api,
    required this.session,
    required this.pointCount,
    required this.notifyEmail,
    required this.savingEmailPreference,
    required this.onNotifyEmailChanged,
    required this.onUserUpdated,
    required this.onSignOut,
    super.key,
  });

  final SmartHydroApi api;
  final SmartHydroSession session;
  final int pointCount;
  final bool notifyEmail;
  final bool savingEmailPreference;
  final ValueChanged<bool> onNotifyEmailChanged;
  final ValueChanged<Map<String, dynamic>> onUserUpdated;
  final VoidCallback onSignOut;

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  final _profileKey = GlobalKey<FormState>();
  final _passwordKey = GlobalKey<FormState>();
  late final TextEditingController _firstName = TextEditingController(
    text: widget.session.user['first_name']?.toString() ?? '',
  );
  late final TextEditingController _lastName = TextEditingController(
    text: widget.session.user['last_name']?.toString() ?? '',
  );
  late final TextEditingController _email = TextEditingController(
    text: widget.session.email,
  );
  final _currentPassword = TextEditingController();
  final _newPassword = TextEditingController();
  final _confirmPassword = TextEditingController();
  bool _editing = false;
  bool _savingProfile = false;
  bool _savingPassword = false;
  bool _obscureCurrent = true;
  bool _obscureNew = true;

  @override
  void didUpdateWidget(covariant ProfileScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (_editing || _savingProfile) return;
    if (oldWidget.session.user == widget.session.user) return;
    _firstName.text = widget.session.user['first_name']?.toString() ?? '';
    _lastName.text = widget.session.user['last_name']?.toString() ?? '';
    _email.text = widget.session.email;
  }

  @override
  void dispose() {
    _firstName.dispose();
    _lastName.dispose();
    _email.dispose();
    _currentPassword.dispose();
    _newPassword.dispose();
    _confirmPassword.dispose();
    super.dispose();
  }

  void _restoreProfile() {
    _firstName.text = widget.session.user['first_name']?.toString() ?? '';
    _lastName.text = widget.session.user['last_name']?.toString() ?? '';
    _email.text = widget.session.email;
  }

  Future<void> _saveProfile() async {
    if (!_profileKey.currentState!.validate()) return;
    setState(() => _savingProfile = true);
    try {
      final user = await widget.api.updateProfile(
        widget.session.token,
        firstName: _firstName.text,
        lastName: _lastName.text,
        email: _email.text,
      );
      if (!mounted) return;
      widget.onUserUpdated({...widget.session.user, ...user});
      setState(() => _editing = false);
      _show('Perfil actualizado.');
    } on SmartHydroApiException catch (error) {
      _show(error.message);
    } finally {
      if (mounted) setState(() => _savingProfile = false);
    }
  }

  Future<void> _savePassword() async {
    if (!_passwordKey.currentState!.validate()) return;
    setState(() => _savingPassword = true);
    try {
      await widget.api.changePassword(
        widget.session.token,
        currentPassword: _currentPassword.text,
        newPassword: _newPassword.text,
      );
      if (!mounted) return;
      _currentPassword.clear();
      _newPassword.clear();
      _confirmPassword.clear();
      _show('Contraseña actualizada.');
    } on SmartHydroApiException catch (error) {
      _show(error.message);
    } finally {
      if (mounted) setState(() => _savingPassword = false);
    }
  }

  void _show(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    final username = widget.session.user['username']?.toString() ?? '';
    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 32),
      children: [
        _Card(
          child: Row(
            children: [
              CircleAvatar(
                radius: 27,
                backgroundColor: const Color(0xFF24454A),
                child: Text(
                  widget.session.displayName.isEmpty
                      ? 'S'
                      : widget.session.displayName.substring(0, 1).toUpperCase(),
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      widget.session.displayName,
                      style: const TextStyle(
                        fontWeight: FontWeight.w800,
                        fontSize: 16,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      widget.session.email,
                      style: const TextStyle(color: Color(0xFF9AB0B1)),
                    ),
                  ],
                ),
              ),
              Text(
                '${widget.pointCount}',
                style: const TextStyle(
                  color: Color(0xFF66E0C2),
                  fontWeight: FontWeight.w800,
                  fontSize: 18,
                ),
              ),
              const SizedBox(width: 6),
              const Text(
                'puntos',
                style: TextStyle(color: Color(0xFF9AB0B1), fontSize: 11),
              ),
            ],
          ),
        ),
        const SizedBox(height: 14),
        _Card(
          child: Form(
            key: _profileKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    const Expanded(
                      child: Text(
                        'Información personal',
                        style: TextStyle(fontWeight: FontWeight.w800),
                      ),
                    ),
                    TextButton(
                      onPressed: _savingProfile
                          ? null
                          : () {
                              if (_editing) _restoreProfile();
                              setState(() => _editing = !_editing);
                            },
                      child: Text(_editing ? 'Cancelar' : 'Editar'),
                    ),
                  ],
                ),
                if (!_editing) ...[
                  _ReadRow(label: 'Nombre', value: _firstName.text),
                  _ReadRow(label: 'Apellido', value: _lastName.text),
                  _ReadRow(label: 'Correo', value: _email.text),
                  _ReadRow(
                    label: 'Usuario',
                    value: username.isEmpty ? 'Sin usuario' : '@$username',
                  ),
                ] else ...[
                  TextFormField(
                    controller: _firstName,
                    decoration: const InputDecoration(labelText: 'Nombre'),
                    textInputAction: TextInputAction.next,
                    validator: (value) =>
                        (value ?? '').trim().isEmpty ? 'Ingresa tu nombre.' : null,
                  ),
                  const SizedBox(height: 10),
                  TextFormField(
                    controller: _lastName,
                    decoration: const InputDecoration(labelText: 'Apellido'),
                    textInputAction: TextInputAction.next,
                    validator: (value) => (value ?? '').trim().isEmpty
                        ? 'Ingresa tu apellido.'
                        : null,
                  ),
                  const SizedBox(height: 10),
                  TextFormField(
                    controller: _email,
                    decoration: const InputDecoration(
                      labelText: 'Correo electrónico',
                    ),
                    keyboardType: TextInputType.emailAddress,
                    validator: (value) {
                      final email = (value ?? '').trim();
                      if (!email.contains('@') || !email.contains('.')) {
                        return 'Ingresa un correo válido.';
                      }
                      return null;
                    },
                  ),
                  const SizedBox(height: 8),
                  Text(
                    username.isEmpty
                        ? 'El usuario de acceso no se modifica aquí.'
                        : 'Usuario @$username. El nombre de usuario no cambia.',
                    style: const TextStyle(
                      color: Color(0xFF809798),
                      fontSize: 11,
                    ),
                  ),
                  const SizedBox(height: 12),
                  FilledButton(
                    onPressed: _savingProfile ? null : _saveProfile,
                    child: Text(
                      _savingProfile ? 'Guardando…' : 'Guardar cambios',
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
        const SizedBox(height: 14),
        _Card(
          child: Form(
            key: _passwordKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Text(
                  'Contraseña',
                  style: TextStyle(fontWeight: FontWeight.w800),
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _currentPassword,
                  obscureText: _obscureCurrent,
                  decoration: InputDecoration(
                    labelText: 'Contraseña actual',
                    suffixIcon: IconButton(
                      onPressed: () =>
                          setState(() => _obscureCurrent = !_obscureCurrent),
                      icon: Icon(
                        _obscureCurrent
                            ? Icons.visibility_outlined
                            : Icons.visibility_off_outlined,
                      ),
                    ),
                  ),
                  validator: (value) => (value ?? '').isEmpty
                      ? 'Ingresa tu contraseña actual.'
                      : null,
                ),
                const SizedBox(height: 10),
                TextFormField(
                  controller: _newPassword,
                  obscureText: _obscureNew,
                  decoration: InputDecoration(
                    labelText: 'Nueva contraseña',
                    suffixIcon: IconButton(
                      onPressed: () =>
                          setState(() => _obscureNew = !_obscureNew),
                      icon: Icon(
                        _obscureNew
                            ? Icons.visibility_outlined
                            : Icons.visibility_off_outlined,
                      ),
                    ),
                  ),
                  validator: (value) {
                    if ((value ?? '').length < 8) {
                      return 'Usa al menos 8 caracteres.';
                    }
                    return null;
                  },
                ),
                const SizedBox(height: 10),
                TextFormField(
                  controller: _confirmPassword,
                  obscureText: true,
                  decoration: const InputDecoration(
                    labelText: 'Confirmar contraseña',
                  ),
                  validator: (value) {
                    if (value != _newPassword.text) {
                      return 'Las contraseñas no coinciden.';
                    }
                    return null;
                  },
                ),
                const SizedBox(height: 12),
                FilledButton(
                  onPressed: _savingPassword ? null : _savePassword,
                  child: Text(
                    _savingPassword ? 'Actualizando…' : 'Cambiar contraseña',
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 14),
        _Card(
          child: SwitchListTile.adaptive(
            contentPadding: EdgeInsets.zero,
            value: widget.notifyEmail,
            onChanged: widget.savingEmailPreference
                ? null
                : widget.onNotifyEmailChanged,
            title: const Text('Avisos por correo'),
            subtitle: const Text(
              'Comentarios y cambios de tus solicitudes de soporte.',
            ),
          ),
        ),
        const SizedBox(height: 18),
        OutlinedButton.icon(
          onPressed: widget.onSignOut,
          icon: const Icon(Icons.logout_rounded),
          label: const Text('Cerrar sesión'),
          style: OutlinedButton.styleFrom(
            minimumSize: const Size.fromHeight(50),
          ),
        ),
      ],
    );
  }
}

class _ReadRow extends StatelessWidget {
  const _ReadRow({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(top: 10),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 88,
          child: Text(
            label,
            style: const TextStyle(color: Color(0xFF9AB0B1), fontSize: 12),
          ),
        ),
        Expanded(
          child: Text(
            value.trim().isEmpty ? 'Sin dato' : value,
            style: const TextStyle(fontWeight: FontWeight.w700),
          ),
        ),
      ],
    ),
  );
}

class _Card extends StatelessWidget {
  const _Card({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(16),
    decoration: BoxDecoration(
      color: const Color(0xFF112328),
      borderRadius: BorderRadius.circular(16),
      border: Border.all(color: Colors.white.withValues(alpha: 0.07)),
    ),
    child: child,
  );
}
