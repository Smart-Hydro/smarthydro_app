import 'package:flutter/material.dart';

import '../../core/api/smarthydro_api.dart';
import '../../core/brand.dart';
import '../../shared/ui/hydro_ui.dart';

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
  bool _obscureConfirm = true;

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
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  String get _savedFirst =>
      widget.session.user['first_name']?.toString().trim() ?? '';

  String get _savedLast =>
      widget.session.user['last_name']?.toString().trim() ?? '';

  String get _fullName {
    final both = [
      _savedFirst,
      _savedLast,
    ].where((part) => part.isNotEmpty).join(' ');
    if (both.isNotEmpty) return both;
    final fallback = widget.session.displayName.trim();
    return fallback.isEmpty ? 'Cuenta' : fallback;
  }

  String get _username {
    final raw = widget.session.user['username']?.toString().trim() ?? '';
    return raw.isEmpty ? '' : '@$raw';
  }

  String get _initial {
    final source = _fullName.trim();
    if (source.isEmpty) return 'S';
    return source.substring(0, 1).toUpperCase();
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final wide = constraints.maxWidth >= 840;
        final pad = wide ? 28.0 : 16.0;
        return ListView(
          key: ValueKey(wide ? 'profile-layout-wide' : 'profile-layout-narrow'),
          padding: EdgeInsets.fromLTRB(pad, wide ? 22 : 14, pad, 96),
          children: [
            const _PageIntro(),
            SizedBox(height: wide ? 16 : 12),
            _IdentityBand(
              initial: _initial,
              name: _fullName,
              email: widget.session.email,
              username: _username,
              pointCount: widget.pointCount,
              wide: wide,
            ),
            SizedBox(height: wide ? 16 : 12),
            if (wide)
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(child: _personalCard(wide: true)),
                  const SizedBox(width: 16),
                  Expanded(child: _passwordCard(wide: true)),
                ],
              )
            else ...[
              _personalCard(wide: false),
              const SizedBox(height: 12),
              _passwordCard(wide: false),
            ],
            const SizedBox(height: 12),
            _notifyCard(),
            const SizedBox(height: 4),
            Align(
              alignment: wide ? Alignment.centerRight : Alignment.center,
              child: TextButton.icon(
                key: const ValueKey('profile-sign-out'),
                onPressed: widget.onSignOut,
                icon: const Icon(Icons.logout_rounded, size: 18),
                label: const Text('Cerrar sesión'),
                style: TextButton.styleFrom(
                  foregroundColor: IkoluColors.incident,
                  minimumSize: Size(wide ? 160 : double.infinity, 48),
                  textStyle: const TextStyle(
                    fontWeight: FontWeight.w700,
                    fontSize: 13,
                  ),
                ),
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _personalCard({required bool wide}) {
    final username = _username;
    return _Sheet(
      child: Form(
        key: _profileKey,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _SectionHead(
              title: 'Información personal',
              trailing: TextButton(
                onPressed: _savingProfile
                    ? null
                    : () {
                        if (_editing) _restoreProfile();
                        setState(() => _editing = !_editing);
                      },
                style: TextButton.styleFrom(
                  foregroundColor: IkoluColors.cyanSoft,
                  visualDensity: VisualDensity.compact,
                  padding: const EdgeInsets.symmetric(horizontal: 10),
                  minimumSize: const Size(64, 36),
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                ),
                child: Text(_editing ? 'Cancelar' : 'Editar'),
              ),
            ),
            if (!_editing) ...[
              _FactGrid(
                facts: [
                  _Fact('Nombre', _blank(_firstName.text)),
                  _Fact('Apellido', _blank(_lastName.text)),
                  _Fact('Correo', _blank(_email.text)),
                  _Fact('Usuario', username.isEmpty ? 'Sin usuario' : username),
                ],
              ),
            ] else ...[
              _pair(_nameField(), _lastNameField()),
              const SizedBox(height: 10),
              TextFormField(
                controller: _email,
                decoration: _fieldDecoration('Correo electrónico'),
                keyboardType: TextInputType.emailAddress,
                autofillHints: const [AutofillHints.email],
                textInputAction: TextInputAction.done,
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
                    : 'Usuario $username. El nombre de usuario no cambia.',
                style: HydroText.hint,
              ),
              const SizedBox(height: 14),
              Align(
                alignment: Alignment.centerRight,
                child: FilledButton(
                  onPressed: _savingProfile ? null : _saveProfile,
                  style: _primaryButton(wide),
                  child: Text(
                    _savingProfile ? 'Guardando…' : 'Guardar cambios',
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _passwordCard({required bool wide}) {
    return _Sheet(
      child: Form(
        key: _passwordKey,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const _SectionHead(title: 'Contraseña'),
            const SizedBox(height: 2),
            Text('Mínimo 8 caracteres.', style: HydroText.hint),
            const SizedBox(height: 12),
            TextFormField(
              controller: _currentPassword,
              obscureText: _obscureCurrent,
              autofillHints: const [AutofillHints.password],
              decoration: _fieldDecoration('Contraseña actual').copyWith(
                suffixIcon: _visibility(
                  hidden: _obscureCurrent,
                  onPressed: () =>
                      setState(() => _obscureCurrent = !_obscureCurrent),
                ),
              ),
              validator: (value) => (value ?? '').isEmpty
                  ? 'Ingresa tu contraseña actual.'
                  : null,
            ),
            const SizedBox(height: 10),
            _pair(_newPasswordField(), _confirmPasswordField()),
            const SizedBox(height: 14),
            Align(
              alignment: Alignment.centerRight,
              child: FilledButton(
                onPressed: _savingPassword ? null : _savePassword,
                style: _primaryButton(wide),
                child: Text(
                  _savingPassword ? 'Actualizando…' : 'Cambiar contraseña',
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _notifyCard() {
    final busy = widget.savingEmailPreference;
    return _Sheet(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          const _IconDisc(icon: Icons.mail_outline_rounded),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Avisos por correo', style: HydroText.section),
                const SizedBox(height: 2),
                Text(
                  'Comentarios y cambios de tus solicitudes de soporte.',
                  style: HydroText.hint,
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Switch(
            value: widget.notifyEmail,
            onChanged: busy ? null : widget.onNotifyEmailChanged,
            thumbColor: WidgetStateProperty.resolveWith((states) {
              if (states.contains(WidgetState.selected)) {
                return const Color(0xFF062026);
              }
              return const Color(0xFFD5E4E2);
            }),
            trackColor: WidgetStateProperty.resolveWith((states) {
              if (states.contains(WidgetState.selected)) {
                return IkoluColors.cyan;
              }
              return Colors.white.withValues(alpha: 0.14);
            }),
          ),
        ],
      ),
    );
  }

  Widget _nameField() {
    return TextFormField(
      controller: _firstName,
      decoration: _fieldDecoration('Nombre'),
      textCapitalization: TextCapitalization.words,
      autofillHints: const [AutofillHints.givenName],
      textInputAction: TextInputAction.next,
      validator: (value) =>
          (value ?? '').trim().isEmpty ? 'Ingresa tu nombre.' : null,
    );
  }

  Widget _lastNameField() {
    return TextFormField(
      controller: _lastName,
      decoration: _fieldDecoration('Apellido'),
      textCapitalization: TextCapitalization.words,
      autofillHints: const [AutofillHints.familyName],
      textInputAction: TextInputAction.next,
      validator: (value) =>
          (value ?? '').trim().isEmpty ? 'Ingresa tu apellido.' : null,
    );
  }

  Widget _newPasswordField() {
    return TextFormField(
      controller: _newPassword,
      obscureText: _obscureNew,
      autofillHints: const [AutofillHints.newPassword],
      decoration: _fieldDecoration('Nueva contraseña').copyWith(
        suffixIcon: _visibility(
          hidden: _obscureNew,
          onPressed: () => setState(() => _obscureNew = !_obscureNew),
        ),
      ),
      validator: (value) {
        if ((value ?? '').length < 8) return 'Usa al menos 8 caracteres.';
        return null;
      },
    );
  }

  Widget _confirmPasswordField() {
    return TextFormField(
      controller: _confirmPassword,
      obscureText: _obscureConfirm,
      decoration: _fieldDecoration('Confirmar contraseña').copyWith(
        suffixIcon: _visibility(
          hidden: _obscureConfirm,
          onPressed: () => setState(() => _obscureConfirm = !_obscureConfirm),
        ),
      ),
      validator: (value) {
        if (value != _newPassword.text) return 'Las contraseñas no coinciden.';
        return null;
      },
    );
  }

  Widget _pair(Widget leading, Widget trailing) {
    return LayoutBuilder(
      builder: (context, constraints) {
        if (constraints.maxWidth < 460) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [leading, const SizedBox(height: 10), trailing],
          );
        }
        return Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(child: leading),
            const SizedBox(width: 12),
            Expanded(child: trailing),
          ],
        );
      },
    );
  }

  Widget _visibility({required bool hidden, required VoidCallback onPressed}) {
    return IconButton(
      onPressed: onPressed,
      icon: Icon(
        hidden ? Icons.visibility_outlined : Icons.visibility_off_outlined,
        size: 18,
        color: const Color(0xFF9AB0B1),
      ),
    );
  }
}

String _blank(String value) => value.trim().isEmpty ? 'Sin dato' : value.trim();

ButtonStyle _primaryButton(bool wide) {
  return FilledButton.styleFrom(
    backgroundColor: IkoluColors.cyan,
    foregroundColor: const Color(0xFF062026),
    disabledBackgroundColor: IkoluColors.cyan.withValues(alpha: 0.35),
    disabledForegroundColor: const Color(0xFF062026).withValues(alpha: 0.6),
    minimumSize: Size(wide ? 168 : double.infinity, 46),
    padding: const EdgeInsets.symmetric(horizontal: 18),
    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
    textStyle: const TextStyle(fontWeight: FontWeight.w800, fontSize: 13),
  );
}

InputDecoration _fieldDecoration(String label) {
  return InputDecoration(
    labelText: label,
    labelStyle: const TextStyle(color: Color(0xFF8FA8A8), fontSize: 13),
    floatingLabelStyle: const TextStyle(color: IkoluColors.cyanSoft),
    filled: true,
    fillColor: const Color(0xFF0C1B20).withValues(alpha: 0.55),
    contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
    border: OutlineInputBorder(
      borderRadius: BorderRadius.circular(14),
      borderSide: BorderSide(color: Colors.white.withValues(alpha: 0.08)),
    ),
    enabledBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(14),
      borderSide: BorderSide(color: IkoluColors.cyan.withValues(alpha: 0.16)),
    ),
    focusedBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(14),
      borderSide: const BorderSide(color: IkoluColors.cyan, width: 1.4),
    ),
    errorBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(14),
      borderSide: const BorderSide(color: IkoluColors.incident),
    ),
    focusedErrorBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(14),
      borderSide: const BorderSide(color: IkoluColors.incident, width: 1.4),
    ),
  );
}

class _SectionHead extends StatelessWidget {
  const _SectionHead({required this.title, this.trailing});

  final String title;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 40,
      child: Row(
        children: [
          Expanded(
            child: Text(
              title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: HydroText.section,
            ),
          ),
          ?trailing,
        ],
      ),
    );
  }
}

class _PageIntro extends StatelessWidget {
  const _PageIntro();

  @override
  Widget build(BuildContext context) {
    return const Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Cuenta', style: HydroText.title),
        SizedBox(height: 4),
        Text(
          'Datos de acceso y avisos de tu sesión.',
          style: HydroText.subtitle,
        ),
      ],
    );
  }
}

class _IdentityBand extends StatelessWidget {
  const _IdentityBand({
    required this.initial,
    required this.name,
    required this.email,
    required this.username,
    required this.pointCount,
    required this.wide,
  });

  final String initial;
  final String name;
  final String email;
  final String username;
  final int pointCount;
  final bool wide;

  @override
  Widget build(BuildContext context) {
    final identity = Row(
      children: [
        _Monogram(initial: initial),
        const SizedBox(width: 14),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: HydroTone.fog,
                  fontSize: 20,
                  fontWeight: FontWeight.w800,
                  letterSpacing: -0.3,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                email.isEmpty ? 'Sin correo' : email,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: HydroText.subtitle,
              ),
              if (username.isNotEmpty) ...[
                const SizedBox(height: 6),
                _UsernameChip(username: username),
              ],
            ],
          ),
        ),
      ],
    );

    final points = _PointsStat(count: pointCount);

    return _Sheet(
      key: const ValueKey('profile-identity'),
      child: wide
          ? Row(
              children: [
                Expanded(child: identity),
                const SizedBox(width: 16),
                points,
              ],
            )
          : Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                identity,
                const SizedBox(height: 14),
                Align(alignment: Alignment.centerLeft, child: points),
              ],
            ),
    );
  }
}

class _Monogram extends StatelessWidget {
  const _Monogram({required this.initial});

  final String initial;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 56,
      height: 56,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            Color.lerp(IkoluColors.cyan, Colors.white, 0.35)!,
            IkoluColors.cyan.withValues(alpha: 0.82),
          ],
        ),
      ),
      child: Text(
        initial,
        style: const TextStyle(
          color: Color(0xFF062026),
          fontSize: 22,
          fontWeight: FontWeight.w800,
        ),
      ),
    );
  }
}

class _UsernameChip extends StatelessWidget {
  const _UsernameChip({required this.username});

  final String username;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(999),
        color: Colors.white.withValues(alpha: 0.06),
        border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
      ),
      child: Text(
        username,
        style: const TextStyle(
          color: Color(0xFFC9D8D8),
          fontSize: 11,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}

class _PointsStat extends StatelessWidget {
  const _PointsStat({required this.count});

  final int count;

  @override
  Widget build(BuildContext context) {
    final label = count == 1 ? 'punto en la red' : 'puntos en la red';
    return Container(
      key: const ValueKey('profile-points'),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(14),
        color: Colors.white.withValues(alpha: 0.05),
        border: Border.all(color: IkoluColors.cyan.withValues(alpha: 0.22)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            '$count',
            style: const TextStyle(
              color: IkoluColors.cyan,
              fontSize: 22,
              fontWeight: FontWeight.w800,
              height: 1,
            ),
          ),
          const SizedBox(width: 8),
          Text(
            label,
            style: const TextStyle(
              color: HydroTone.faint,
              fontSize: 12,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}

class _Fact {
  const _Fact(this.label, this.value);

  final String label;
  final String value;
}

class _FactGrid extends StatelessWidget {
  const _FactGrid({required this.facts});

  final List<_Fact> facts;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final two = constraints.maxWidth >= 420;
        if (!two) {
          return Column(
            children: [for (final fact in facts) _FactTile(fact: fact)],
          );
        }
        final rows = <Widget>[];
        for (var i = 0; i < facts.length; i += 2) {
          final right = i + 1 < facts.length ? facts[i + 1] : null;
          rows.add(
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(child: _FactTile(fact: facts[i])),
                const SizedBox(width: 16),
                Expanded(
                  child: right == null
                      ? const SizedBox.shrink()
                      : _FactTile(fact: right),
                ),
              ],
            ),
          );
        }
        return Column(children: rows);
      },
    );
  }
}

class _FactTile extends StatelessWidget {
  const _FactTile({required this.fact});

  final _Fact fact;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            fact.label,
            style: const TextStyle(
              color: HydroTone.faint,
              fontSize: 11,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            fact.value,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              color: HydroTone.fog,
              fontSize: 14,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}

class _IconDisc extends StatelessWidget {
  const _IconDisc({required this.icon});

  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 40,
      height: 40,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: IkoluColors.cyan.withValues(alpha: 0.12),
      ),
      child: Icon(icon, size: 18, color: IkoluColors.cyanSoft),
    );
  }
}

class _Sheet extends StatelessWidget {
  const _Sheet({required this.child, super.key});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(20),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            Colors.white.withValues(alpha: 0.08),
            IkoluColors.cyan.withValues(alpha: 0.05),
            const Color(0xFF0C1A1E).withValues(alpha: 0.42),
          ],
        ),
        border: Border.all(color: Colors.white.withValues(alpha: 0.10)),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
        child: child,
      ),
    );
  }
}
