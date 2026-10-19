import 'dart:math' as math;

import 'package:flutter/material.dart';

/// Colores de las vistas de detalle (análisis, cumplimiento, registros).
abstract final class HydroTone {
  static const bg = Color(0xFF0A181D);
  static const bgGlow = Color(0xFF143038);
  static const fog = Color(0xFFE8F2F1);
  static const faint = Color(0xFF9AB0B1);
  static const hair = Color(0x14FFFFFF);
  static const accent = Color(0xFF7FD3FF);
  static const level = Color(0xFFB7A6FF);
  static const menu = Color(0xFF12292F);
}

abstract final class HydroText {
  static const title = TextStyle(
    color: HydroTone.fog,
    fontSize: 20,
    fontWeight: FontWeight.w800,
    letterSpacing: -0.4,
  );
  static const subtitle = TextStyle(
    color: HydroTone.faint,
    fontSize: 12,
    fontWeight: FontWeight.w600,
  );
  static const section = TextStyle(
    color: HydroTone.fog,
    fontSize: 14,
    fontWeight: FontWeight.w800,
  );
  static const sectionTrailing = TextStyle(
    color: HydroTone.faint,
    fontSize: 11,
    fontWeight: FontWeight.w600,
  );
  static final hint = TextStyle(
    color: HydroTone.faint.withValues(alpha: 0.85),
    fontSize: 11,
    fontWeight: FontWeight.w600,
    height: 1.35,
  );
}

abstract final class HydroMotion {
  static const fast = Duration(milliseconds: 200);
  static const medium = Duration(milliseconds: 320);

  /// Cambio de pantalla completa: rutas, pestañas, login ↔ dashboard.
  static const page = Duration(milliseconds: 300);
  static const pageReverse = Duration(milliseconds: 240);
  static const curve = Curves.easeOutCubic;

  static Duration of(BuildContext context, Duration d) =>
      MediaQuery.maybeDisableAnimationsOf(context) ?? false ? Duration.zero : d;
}

/// Calendario de rango: en escritorio es un modal chico; en el teléfono
/// sigue ocupando la pantalla para que se pueda tocar.
Future<DateTimeRange?> showHydroDateRange({
  required BuildContext context,
  required DateTime firstDate,
  required DateTime lastDate,
  DateTimeRange? initialDateRange,
  String? helpText,
  String? saveText,
}) {
  final compact = MediaQuery.sizeOf(context).width >= 720;
  const panel = Size(400, 520);
  return showDateRangePicker(
    context: context,
    firstDate: firstDate,
    lastDate: lastDate,
    initialDateRange: initialDateRange,
    helpText: helpText,
    saveText: saveText,
    barrierColor: Colors.black.withValues(alpha: compact ? 0.34 : 0.54),
    barrierDismissible: true,
    builder: (context, child) {
      if (child == null) return const SizedBox.shrink();
      if (!compact) return child;
      return Center(
        child: ClipRRect(
          borderRadius: BorderRadius.circular(22),
          child: ConstrainedBox(
            constraints: BoxConstraints.tight(panel),
            child: MediaQuery(
              data: MediaQuery.of(context).copyWith(size: panel),
              child: child,
            ),
          ),
        ),
      );
    },
  );
}

/// Fondo con halo superior y columna centrada; cabecera con volver.
class HydroPage extends StatelessWidget {
  const HydroPage({
    required this.title,
    required this.body,
    this.subtitle,
    this.trailing,
    this.onBack,
    this.showBack = true,
    this.titleLeading,
    this.floatingActionButton,
    this.maxWidth = 760,
    super.key,
  });

  final String title;
  final Widget? subtitle;
  final Widget? trailing;
  final Widget? titleLeading;
  final Widget? floatingActionButton;
  final Widget body;
  final double maxWidth;

  /// Si viene, Volver no hace pop.
  final VoidCallback? onBack;

  /// En el shell de escritorio va en false: el rail sigue a la vista.
  final bool showBack;

  @override
  Widget build(BuildContext context) {
    final wide = MediaQuery.sizeOf(context).width >= 1100;
    final cap = wide ? math.max(maxWidth, 1080.0) : maxWidth;
    return Scaffold(
      backgroundColor: Colors.transparent,
      floatingActionButton: floatingActionButton,
      body: SafeArea(
        child: Align(
          alignment: Alignment.topCenter,
          child: ConstrainedBox(
            constraints: BoxConstraints(maxWidth: cap),
            child: Column(
              children: [
                HydroHeader(
                  title: title,
                  subtitle: subtitle,
                  trailing: trailing,
                  titleLeading: titleLeading,
                  onBack: onBack,
                  showBack: showBack,
                ),
                Expanded(child: body),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class HydroHeader extends StatelessWidget {
  const HydroHeader({
    required this.title,
    this.subtitle,
    this.trailing,
    this.titleLeading,
    this.onBack,
    this.showBack = true,
    super.key,
  });

  final String title;
  final Widget? subtitle;
  final Widget? trailing;
  final Widget? titleLeading;
  final VoidCallback? onBack;
  final bool showBack;

  @override
  Widget build(BuildContext context) {
    final hasTitle = title.isNotEmpty;
    if (!showBack &&
        !hasTitle &&
        subtitle == null &&
        trailing == null &&
        titleLeading == null) {
      return const SizedBox.shrink();
    }
    return Padding(
      padding: EdgeInsets.fromLTRB(showBack ? 8 : 20, 8, 12, 4),
      child: Row(
        children: [
          if (showBack) ...[
            HydroBackButton(onPressed: onBack),
            const SizedBox(width: 4),
          ],
          if (titleLeading != null) ...[
            titleLeading!,
            const SizedBox(width: 10),
          ],
          if (hasTitle || subtitle != null)
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (hasTitle)
                    Text(
                      title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: HydroText.title,
                    ),
                  ?subtitle,
                ],
              ),
            )
          else
            const Spacer(),
          ?trailing,
        ],
      ),
    );
  }
}

/// Vidrio claro: sin borde ni color, solo un velo luminoso y una sombra.
class HydroGlassLight extends StatelessWidget {
  const HydroGlassLight({
    required this.child,
    this.padding = const EdgeInsets.all(14),
    this.radius = 16,
    this.strength = 1,
    super.key,
  });

  final Widget child;
  final EdgeInsets padding;
  final double radius;

  /// 0–1: cuánto se nota el velo.
  final double strength;

  @override
  Widget build(BuildContext context) => DecoratedBox(
    decoration: BoxDecoration(
      borderRadius: BorderRadius.circular(radius),
      gradient: LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [
          Colors.white.withValues(alpha: 0.075 * strength),
          Colors.white.withValues(alpha: 0.03 * strength),
        ],
      ),
      boxShadow: [
        BoxShadow(
          color: Colors.black.withValues(alpha: 0.22 * strength),
          blurRadius: 22,
          offset: const Offset(0, 10),
        ),
      ],
    ),
    child: Padding(padding: padding, child: child),
  );
}

/// Volver sin borde: solo el icono, con un halo suave al pasar o presionar.
class HydroBackButton extends StatefulWidget {
  const HydroBackButton({this.onPressed, this.backdrop = false, super.key});

  final VoidCallback? onPressed;

  /// Fondo translúcido para cuando va sobre una escena y no sobre el fondo.
  final bool backdrop;

  @override
  State<HydroBackButton> createState() => _HydroBackButtonState();
}

class _HydroBackButtonState extends State<HydroBackButton> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final duration = HydroMotion.of(context, HydroMotion.fast);
    final fill = widget.backdrop
        ? Colors.black.withValues(alpha: _hovered ? 0.34 : 0.22)
        : Colors.white.withValues(alpha: _hovered ? 0.07 : 0);
    return Tooltip(
      message: 'Volver',
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        onEnter: (_) => setState(() => _hovered = true),
        onExit: (_) => setState(() => _hovered = false),
        child: Material(
          type: MaterialType.transparency,
          child: InkWell(
            customBorder: const CircleBorder(),
            splashColor: HydroTone.accent.withValues(alpha: 0.12),
            highlightColor: Colors.transparent,
            onTap: widget.onPressed ?? () => Navigator.of(context).maybePop(),
            child: AnimatedContainer(
              duration: duration,
              curve: HydroMotion.curve,
              width: 42,
              height: 42,
              decoration: BoxDecoration(color: fill, shape: BoxShape.circle),
              child: AnimatedSlide(
                duration: duration,
                curve: HydroMotion.curve,
                offset: Offset(_hovered ? -0.06 : 0, 0),
                child: Icon(
                  Icons.arrow_back_rounded,
                  size: 22,
                  color: _hovered ? HydroTone.fog : const Color(0xFFC9D8D8),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class HydroSectionTitle extends StatelessWidget {
  const HydroSectionTitle({required this.title, this.trailing, super.key});

  final String title;
  final String? trailing;

  @override
  Widget build(BuildContext context) => Row(
    crossAxisAlignment: CrossAxisAlignment.baseline,
    textBaseline: TextBaseline.alphabetic,
    children: [
      Flexible(
        child: Text(
          title,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: HydroText.section,
        ),
      ),
      if (trailing != null) ...[
        const SizedBox(width: 8),
        Flexible(
          child: Text(
            trailing!,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: HydroText.sectionTrailing,
          ),
        ),
      ],
    ],
  );
}

class HydroHint extends StatelessWidget {
  const HydroHint(this.text, {super.key});

  final String text;

  @override
  Widget build(BuildContext context) => Text(text, style: HydroText.hint);
}

/// Estado vacío o de error, centrado, con una acción opcional.
class HydroMessage extends StatelessWidget {
  const HydroMessage({
    required this.icon,
    required this.title,
    required this.message,
    this.action,
    super.key,
  });

  final IconData icon;
  final String title;
  final String message;
  final (String, VoidCallback)? action;

  @override
  Widget build(BuildContext context) => Center(
    child: Padding(
      padding: const EdgeInsets.all(28),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: HydroTone.accent, size: 30),
          const SizedBox(height: 10),
          Text(
            title,
            textAlign: TextAlign.center,
            style: const TextStyle(
              color: HydroTone.fog,
              fontSize: 15,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            message,
            textAlign: TextAlign.center,
            style: const TextStyle(
              color: HydroTone.faint,
              fontSize: 12,
              height: 1.35,
            ),
          ),
          if (action != null) ...[
            const SizedBox(height: 14),
            TextButton(
              onPressed: action!.$2,
              style: TextButton.styleFrom(
                foregroundColor: HydroTone.accent,
                backgroundColor: HydroTone.accent.withValues(alpha: 0.10),
                shape: const StadiumBorder(),
              ),
              child: Text(action!.$1),
            ),
          ],
        ],
      ),
    ),
  );
}

/// Pestañas de texto con subrayado corto bajo la elegida.
class HydroTabs<T> extends StatelessWidget {
  const HydroTabs({
    required this.values,
    required this.selected,
    required this.label,
    required this.onChanged,
    this.fontSize = 12.5,
    super.key,
  });

  final List<T> values;
  final T selected;
  final String Function(T value) label;
  final ValueChanged<T> onChanged;
  final double fontSize;

  @override
  Widget build(BuildContext context) {
    final fast = HydroMotion.of(context, HydroMotion.fast);
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (final value in values)
          Semantics(
            button: true,
            selected: value == selected,
            child: InkWell(
              borderRadius: BorderRadius.circular(10),
              onTap: () => onChanged(value),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    AnimatedDefaultTextStyle(
                      duration: fast,
                      style: TextStyle(
                        color: value == selected
                            ? HydroTone.fog
                            : HydroTone.faint,
                        fontSize: fontSize,
                        fontWeight: value == selected
                            ? FontWeight.w800
                            : FontWeight.w600,
                      ),
                      child: Text(label(value)),
                    ),
                    const SizedBox(height: 4),
                    AnimatedContainer(
                      duration: fast,
                      curve: HydroMotion.curve,
                      width: value == selected ? 16 : 0,
                      height: 2,
                      decoration: BoxDecoration(
                        color: HydroTone.accent,
                        borderRadius: BorderRadius.circular(1),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
      ],
    );
  }
}

/// Entrada escalonada de una pieza al terminar de cargar.
class HydroReveal extends StatelessWidget {
  const HydroReveal({
    required this.animation,
    required this.index,
    required this.child,
    super.key,
  });

  final Animation<double> animation;
  final int index;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final start = math.min(index * 0.05, 0.5);
    final curved = CurvedAnimation(
      parent: animation,
      curve: Interval(start, start + 0.5, curve: HydroMotion.curve),
    );
    return FadeTransition(
      opacity: curved,
      child: SlideTransition(
        position: Tween(
          begin: const Offset(0, 0.08),
          end: Offset.zero,
        ).animate(curved),
        child: child,
      ),
    );
  }
}

/// Cambio suave entre estados (carga, error, contenido). [state] identifica
/// cuál se muestra: al cambiar, el anterior se desvanece y el nuevo sube.
class HydroSwap extends StatelessWidget {
  const HydroSwap({required this.state, required this.child, super.key});

  final Object state;
  final Widget child;

  @override
  Widget build(BuildContext context) => AnimatedSwitcher(
    duration: HydroMotion.of(context, HydroMotion.medium),
    switchInCurve: HydroMotion.curve,
    switchOutCurve: Curves.easeInCubic,
    layoutBuilder: (current, previous) => Stack(
      alignment: Alignment.topCenter,
      children: [...previous, ?current],
    ),
    transitionBuilder: (child, animation) => FadeTransition(
      opacity: animation,
      child: SlideTransition(
        position: Tween(
          begin: const Offset(0, 0.015),
          end: Offset.zero,
        ).animate(animation),
        child: child,
      ),
    ),
    child: KeyedSubtree(key: ValueKey(state), child: child),
  );
}

// ------------------------------------------------------------ skeleton

/// Brillo que recorre los huesos de su subárbol. Uno por pantalla basta.
class HydroShimmer extends StatefulWidget {
  const HydroShimmer({required this.child, super.key});

  final Widget child;

  @override
  State<HydroShimmer> createState() => _HydroShimmerState();
}

class _HydroShimmerState extends State<HydroShimmer>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1500),
  );

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (MediaQuery.maybeDisableAnimationsOf(context) ?? false) {
      _controller.stop();
      _controller.value = 0.5;
    } else if (!_controller.isAnimating) {
      _controller.repeat();
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: _controller,
    child: widget.child,
    builder: (context, child) => ShaderMask(
      blendMode: BlendMode.srcATop,
      shaderCallback: (bounds) => LinearGradient(
        begin: Alignment.centerLeft,
        end: Alignment.centerRight,
        colors: [
          Colors.white.withValues(alpha: 0.04),
          Colors.white.withValues(alpha: 0.11),
          Colors.white.withValues(alpha: 0.04),
        ],
        stops: const [0.3, 0.5, 0.7],
        transform: _SlideGradient(_controller.value),
      ).createShader(bounds),
      child: child,
    ),
  );
}

class _SlideGradient extends GradientTransform {
  const _SlideGradient(this.t);

  final double t;

  @override
  Matrix4 transform(Rect bounds, {TextDirection? textDirection}) =>
      Matrix4.translationValues(bounds.width * (t * 2.4 - 1.2), 0, 0);
}

/// Forma gris de un dato que todavía no llega.
class HydroBone extends StatelessWidget {
  const HydroBone({
    this.width,
    this.height = 10,
    this.radius = 6,
    this.circle = false,
    super.key,
  });

  final double? width;
  final double height;
  final double radius;
  final bool circle;

  @override
  Widget build(BuildContext context) => Container(
    width: circle ? height : width,
    height: height,
    decoration: BoxDecoration(
      color: Colors.white.withValues(alpha: 0.06),
      shape: circle ? BoxShape.circle : BoxShape.rectangle,
      borderRadius: circle ? null : BorderRadius.circular(radius),
    ),
  );
}

/// Fila de lista: icono, dos líneas y un valor a la derecha.
class HydroBoneRow extends StatelessWidget {
  const HydroBoneRow({this.leading = true, this.seed = 0, super.key});

  final bool leading;
  final int seed;

  @override
  Widget build(BuildContext context) {
    final w = 0.42 + (seed * 0.137) % 0.3;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 10),
      child: Row(
        children: [
          if (leading) ...[
            const HydroBone(height: 34, circle: true),
            const SizedBox(width: 12),
          ],
          Expanded(
            child: LayoutBuilder(
              builder: (context, c) => Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  HydroBone(width: c.maxWidth * w, height: 11),
                  const SizedBox(height: 7),
                  HydroBone(width: c.maxWidth * (w * 0.6), height: 8),
                ],
              ),
            ),
          ),
          const SizedBox(width: 12),
          const HydroBone(width: 46, height: 12),
        ],
      ),
    );
  }
}

/// Tarjetas grises mientras llega una lista.
class HydroSkeletonCards extends StatelessWidget {
  const HydroSkeletonCards({this.count = 4, this.height = 84, super.key});

  final int count;
  final double height;

  @override
  Widget build(BuildContext context) => Semantics(
    label: 'Cargando',
    child: HydroShimmer(
      child: Column(
        children: [
          for (var i = 0; i < count; i++)
            Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: HydroBone(height: height, radius: 16),
            ),
        ],
      ),
    ),
  );
}

/// Esqueleto de una vista de detalle. Cada bloque se activa según lo que la
/// pantalla va a mostrar, para que el contenido real caiga en su lugar.
class HydroSkeleton extends StatelessWidget {
  const HydroSkeleton({
    this.caption,
    this.progress,
    this.tabs = false,
    this.hero = true,
    this.kpis = 3,
    this.chart = true,
    this.rows = 4,
    this.padding = const EdgeInsets.fromLTRB(20, 4, 20, 32),
    this.inline = false,
    super.key,
  });

  /// Lo que se está leyendo, para que la espera tenga sentido.
  final String? caption;

  /// 0–1 cuando se conoce el avance.
  final double? progress;
  final bool tabs;
  final bool hero;
  final int kpis;
  final bool chart;
  final int rows;
  final EdgeInsets padding;

  /// Dentro de otra lista: toma solo su alto y no agrega márgenes.
  final bool inline;

  @override
  Widget build(BuildContext context) => Semantics(
    label: caption ?? 'Cargando',
    child: ListView(
      physics: const NeverScrollableScrollPhysics(),
      shrinkWrap: inline,
      padding: inline ? EdgeInsets.zero : padding,
      children: [
        if (caption != null) ...[
          _SkeletonCaption(text: caption!, progress: progress),
          const SizedBox(height: 16),
        ],
        HydroShimmer(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (tabs) ...[
                const Row(
                  children: [
                    HydroBone(width: 34, height: 12),
                    SizedBox(width: 18),
                    HydroBone(width: 34, height: 12),
                    SizedBox(width: 18),
                    HydroBone(width: 34, height: 12),
                  ],
                ),
                const SizedBox(height: 22),
              ],
              if (hero) ...[
                const Row(
                  children: [
                    HydroBone(height: 92, circle: true),
                    SizedBox(width: 18),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          HydroBone(width: 150, height: 16),
                          SizedBox(height: 10),
                          HydroBone(height: 9),
                          SizedBox(height: 7),
                          HydroBone(width: 180, height: 9),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 26),
              ],
              if (kpis > 0) ...[
                const HydroBone(width: 110, height: 12),
                const SizedBox(height: 12),
                Row(
                  children: [
                    for (var i = 0; i < kpis; i++) ...[
                      if (i > 0) const SizedBox(width: 10),
                      const Expanded(child: HydroBone(height: 64, radius: 16)),
                    ],
                  ],
                ),
                const SizedBox(height: 26),
              ],
              if (chart) ...[
                const HydroBone(width: 130, height: 12),
                const SizedBox(height: 12),
                const HydroBone(height: 150, radius: 18),
                const SizedBox(height: 22),
              ],
              for (var i = 0; i < rows; i++) HydroBoneRow(seed: i),
            ],
          ),
        ),
      ],
    ),
  );
}

class _SkeletonCaption extends StatelessWidget {
  const _SkeletonCaption({required this.text, this.progress});

  final String text;
  final double? progress;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(
        text,
        style: const TextStyle(
          color: HydroTone.faint,
          fontSize: 12,
          fontWeight: FontWeight.w700,
        ),
      ),
      if (progress != null) ...[
        const SizedBox(height: 8),
        ClipRRect(
          borderRadius: BorderRadius.circular(2),
          child: TweenAnimationBuilder<double>(
            tween: Tween(end: progress!.clamp(0.0, 1.0)),
            duration: HydroMotion.of(context, HydroMotion.medium),
            builder: (context, v, _) => LinearProgressIndicator(
              value: v,
              minHeight: 2,
              color: HydroTone.accent,
              backgroundColor: Colors.white.withValues(alpha: 0.06),
            ),
          ),
        ),
      ],
    ],
  );
}
