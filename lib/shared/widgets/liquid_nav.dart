import 'dart:ui' as ui;
import 'package:flutter/material.dart';

import '../../core/brand.dart';
import 'workstation_backdrop.dart';

class LiquidDestination {
  const LiquidDestination({required this.icon, required this.label});

  final IconData icon;
  final String label;
}

const liquidDestinations = <LiquidDestination>[
  LiquidDestination(icon: Icons.sensors_rounded, label: 'IoT'),
  LiquidDestination(icon: Icons.terminal_rounded, label: 'Eventos'),
  LiquidDestination(icon: Icons.apps_rounded, label: 'Apps'),
  LiquidDestination(icon: Icons.person_outline_rounded, label: 'Perfil'),
];

/// Atajo de app en el rail desktop y el hub Apps.
class LiquidAppShortcut {
  const LiquidAppShortcut({
    required this.icon,
    required this.label,
    required this.color,
    this.subtitle = '',
    this.adornments = const [],
    this.comingSoon = false,
  });

  final IconData icon;
  final String label;
  final Color color;
  final String subtitle;
  final List<String> adornments;
  final bool comingSoon;
}

/// Apps del escritorio — mismo orden que el hub Apps.
const liquidDesktopApps = <LiquidAppShortcut>[
  LiquidAppShortcut(
    icon: Icons.public_rounded,
    label: 'Ubicaciones',
    subtitle: 'Mapa vivo de captaciones, loggers y enlaces de la red',
    adornments: ['por punto', 'mapa', 'terreno'],
    color: IkoluColors.cyan,
  ),
  LiquidAppShortcut(
    icon: Icons.query_stats_rounded,
    label: 'Análisis',
    subtitle: 'Caudal, tendencias y comparación entre pozos',
    adornments: ['por punto', 'caudal', 'tendencia'],
    color: IkoluColors.info,
  ),
  LiquidAppShortcut(
    icon: Icons.balance_rounded,
    label: 'Cumplimiento',
    subtitle: 'Límites DGA, vigilancia y margen de cada punto',
    adornments: ['DGA', 'por punto', 'alerta'],
    color: IkoluColors.connected,
  ),
  LiquidAppShortcut(
    icon: Icons.smart_toy_outlined,
    label: 'Asistente',
    subtitle: 'Pregunta a N1 con el contexto de tus puntos',
    adornments: ['N1', 'chat', 'por punto'],
    color: IkoluColors.cyanSoft,
  ),
  LiquidAppShortcut(
    icon: Icons.support_agent_rounded,
    label: 'Soporte',
    subtitle: 'Tickets SLA, incidencias y seguimiento abierto',
    adornments: ['SLA', 'tickets', 'por punto'],
    color: IkoluColors.warning,
  ),
  LiquidAppShortcut(
    icon: Icons.table_view_outlined,
    label: 'Registros',
    subtitle: 'Lecturas del período y descarga limpia a CSV',
    adornments: ['CSV', 'histórico', 'por punto'],
    color: Color(0xFFC5D5D4),
  ),
  LiquidAppShortcut(
    icon: Icons.description_outlined,
    label: 'Informes',
    subtitle: 'Resúmenes listos para compartir · en preparación',
    adornments: ['pronto', 'red'],
    color: Color(0xFF7FD3FF),
    comingSoon: true,
  ),
];

/// Eventos es el segundo destino. El conteo de no leídos va en ese ítem.
const liquidAvisosIndex = 1;

/// Apps es el tercer destino (atajos del rail y «Ver todas»).
const liquidAppsIndex = 2;

/// Perfil es el último destino del menú.
const liquidProfileIndex = 3;

/// Ancho del rail desktop: 6 celdas de la grilla workstation.
const liquidNavRailWidth = workstationGridStep * 6;

/// Alto de cada destino principal: 5 celdas.
const liquidNavRailSlot = workstationGridStep * 5;

/// Alto de cada atajo de app: 5 celdas (mismo ritmo que los destinos).
const liquidNavRailAppSlot = workstationGridStep * 5;

/// Separador entre destinos y apps.
const liquidNavRailDivider = workstationGridStep;

/// Margen exterior del rail flotante.
const liquidNavRailInset = workstationGridStep;

/// Espacio horizontal que el contenido debe dejar al rail en desktop.
const liquidNavRailExtent = liquidNavRailWidth + liquidNavRailInset * 2;

class LiquidNavBar extends StatelessWidget {
  const LiquidNavBar({
    required this.selectedIndex,
    required this.unreadCount,
    required this.onSelect,
    super.key,
  });

  final int selectedIndex;
  final int unreadCount;
  final ValueChanged<int> onSelect;

  @override
  Widget build(BuildContext context) {
    final reduce = MediaQuery.of(context).disableAnimations;
    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(28),
          child: BackdropFilter(
            filter: ui.ImageFilter.blur(sigmaX: 20, sigmaY: 20),
            child: Container(
              height: 66,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(28),
                color: const Color(0xFFF4FBFA).withValues(alpha: 0.14),
                boxShadow: [
                  BoxShadow(
                    color: const Color(0xFF001217).withValues(alpha: 0.22),
                    blurRadius: 18,
                    offset: const Offset(0, 8),
                  ),
                  BoxShadow(
                    color: IkoluColors.cyan.withValues(alpha: 0.04),
                    blurRadius: 18,
                    spreadRadius: -2,
                    offset: const Offset(0, -2),
                  ),
                ],
              ),
              child: LayoutBuilder(
                builder: (context, constraints) {
                  final count = liquidDestinations.length;
                  final slot = constraints.maxWidth / count;
                  return Stack(
                    children: [
                      AnimatedPositioned(
                        duration: reduce
                            ? Duration.zero
                            : const Duration(milliseconds: 460),
                        curve: Curves.easeOutCubic,
                        left: slot * selectedIndex + (slot - 54) / 2,
                        top: 8,
                        width: 54,
                        height: 50,
                        child: const _LiquidBlob(),
                      ),
                      Row(
                        children: [
                          for (var index = 0; index < count; index++)
                            Expanded(
                              child: _LiquidHit(
                                destination: liquidDestinations[index],
                                selected: index == selectedIndex,
                                badge: index == liquidAvisosIndex
                                    ? unreadCount
                                    : 0,
                                onTap: () => onSelect(index),
                              ),
                            ),
                        ],
                      ),
                    ],
                  );
                },
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Rail vertical glass para desktop (≥980). Destinos fijos + atajos.
/// Sin scroll: si no caben atajos, se ocultan y queda «Ver todas» → Apps.
class LiquidNavRail extends StatelessWidget {
  const LiquidNavRail({
    required this.selectedIndex,
    required this.unreadCount,
    required this.onSelect,
    required this.onOpenApp,
    super.key,
  });

  final int selectedIndex;
  final int unreadCount;
  final ValueChanged<int> onSelect;
  final ValueChanged<int> onOpenApp;

  static const _minDestSlot = workstationGridStep * 3.5;
  static const _minAppSlot = workstationGridStep * 3.5;
  static const _moreSlot = workstationGridStep * 4;

  @override
  Widget build(BuildContext context) {
    final reduce = MediaQuery.of(context).disableAnimations;
    final destCount = liquidDestinations.length;
    final appCount = liquidDesktopApps.length;

    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: liquidNavRailInset,
        vertical: liquidNavRailInset,
      ),
      child: Align(
        alignment: Alignment.centerLeft,
        child: ClipRRect(
          borderRadius: BorderRadius.circular(24),
          child: BackdropFilter(
            filter: ui.ImageFilter.blur(sigmaX: 18, sigmaY: 18),
            child: Container(
              key: const ValueKey('liquid-nav-rail'),
              width: liquidNavRailWidth,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(24),
                color: const Color(0xFFF4FBFA).withValues(alpha: 0.12),
                border: Border.all(
                  color: Colors.white.withValues(alpha: 0.08),
                ),
                boxShadow: [
                  BoxShadow(
                    color: const Color(0xFF001217).withValues(alpha: 0.28),
                    blurRadius: 22,
                    offset: const Offset(0, 10),
                  ),
                ],
              ),
              child: LayoutBuilder(
                builder: (context, constraints) {
                  final maxH = constraints.hasBoundedHeight
                      ? constraints.maxHeight
                      : MediaQuery.sizeOf(context).height -
                            liquidNavRailInset * 2 -
                            MediaQuery.paddingOf(context).vertical;

                  var destSlot = liquidNavRailSlot.toDouble();
                  var appSlot = liquidNavRailAppSlot.toDouble();
                  final idealAll =
                      destSlot * destCount +
                      liquidNavRailDivider +
                      appSlot * appCount;

                  if (maxH < idealAll) {
                    final destBlockIdeal = destSlot * destCount;
                    final roomForDest = maxH - liquidNavRailDivider - _moreSlot;
                    if (roomForDest < destBlockIdeal) {
                      destSlot = (roomForDest / destCount).clamp(
                        _minDestSlot,
                        liquidNavRailSlot.toDouble(),
                      );
                    }
                    final leftAfterDest =
                        maxH - destSlot * destCount - liquidNavRailDivider;
                    final canShowAllApps =
                        leftAfterDest >= appSlot * appCount - 0.5;
                    if (!canShowAllApps) {
                      appSlot = _minAppSlot;
                    }
                  }

                  final destBlock = destSlot * destCount;
                  final leftForApps =
                      maxH - destBlock - liquidNavRailDivider;
                  final showAllApps =
                      leftForApps >= liquidNavRailAppSlot * appCount - 0.5 ||
                      leftForApps >= appSlot * appCount - 0.5;
                  var visibleApps = 0;
                  var showMore = false;
                  if (showAllApps &&
                      leftForApps >= appSlot * appCount - 0.5) {
                    visibleApps = appCount;
                    appSlot = (leftForApps / appCount).clamp(
                      _minAppSlot,
                      liquidNavRailAppSlot.toDouble(),
                    );
                    // Prefer ideal size when there is room.
                    if (leftForApps >= liquidNavRailAppSlot * appCount) {
                      appSlot = liquidNavRailAppSlot.toDouble();
                    }
                  } else {
                    showMore = true;
                    final room = leftForApps - _moreSlot;
                    if (room >= appSlot) {
                      visibleApps = (room / appSlot).floor().clamp(0, appCount);
                    }
                    // Reclaim space into slightly taller app slots if few show.
                    if (visibleApps > 0) {
                      final slotRoom = room / visibleApps;
                      appSlot = slotRoom.clamp(
                        _minAppSlot,
                        liquidNavRailAppSlot.toDouble(),
                      );
                      visibleApps = (room / appSlot).floor().clamp(0, appCount);
                    }
                  }

                  final bodyHeight =
                      destBlock +
                      liquidNavRailDivider +
                      appSlot * visibleApps +
                      (showMore ? _moreSlot : 0);

                  return SizedBox(
                    height: bodyHeight.clamp(destBlock, maxH),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        SizedBox(
                          height: destBlock,
                          child: Stack(
                            children: [
                              AnimatedPositioned(
                                duration: reduce
                                    ? Duration.zero
                                    : const Duration(milliseconds: 460),
                                curve: Curves.easeOutCubic,
                                top: destSlot * selectedIndex + 6,
                                left: 10,
                                right: 10,
                                height: destSlot - 12,
                                child: const _LiquidBlob(),
                              ),
                              Column(
                                children: [
                                  for (
                                    var index = 0;
                                    index < destCount;
                                    index++
                                  )
                                    SizedBox(
                                      height: destSlot,
                                      width: liquidNavRailWidth,
                                      child: _LiquidHit(
                                        destination: liquidDestinations[index],
                                        selected: index == selectedIndex,
                                        badge: index == liquidAvisosIndex
                                            ? unreadCount
                                            : 0,
                                        iconSize: destSlot < liquidNavRailSlot
                                            ? 22
                                            : 26,
                                        labelSize: destSlot < liquidNavRailSlot
                                            ? 10
                                            : 11,
                                        onTap: () => onSelect(index),
                                      ),
                                    ),
                                ],
                              ),
                            ],
                          ),
                        ),
                        SizedBox(
                          height: liquidNavRailDivider,
                          child: Center(
                            child: Container(
                              height: 1,
                              margin: const EdgeInsets.symmetric(
                                horizontal: 18,
                              ),
                              color: Colors.white.withValues(alpha: 0.10),
                            ),
                          ),
                        ),
                        KeyedSubtree(
                          key: const ValueKey('liquid-nav-rail-apps'),
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              for (
                                var index = 0;
                                index < visibleApps;
                                index++
                              )
                                SizedBox(
                                  height: appSlot,
                                  width: liquidNavRailWidth,
                                  child: _RailAppHit(
                                    app: liquidDesktopApps[index],
                                    onTap: () => onOpenApp(index),
                                    compact: appSlot < liquidNavRailAppSlot,
                                  ),
                                ),
                              if (showMore)
                                SizedBox(
                                  height: _moreSlot,
                                  width: liquidNavRailWidth,
                                  child: _RailMoreHit(
                                    onTap: () => onSelect(liquidAppsIndex),
                                  ),
                                ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  );
                },
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _LiquidBlob extends StatelessWidget {
  const _LiquidBlob();

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(18),
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            IkoluColors.cyan.withValues(alpha: 0.22),
            IkoluColors.navy.withValues(alpha: 0.16),
          ],
        ),
        boxShadow: [
          BoxShadow(
            color: IkoluColors.cyan.withValues(alpha: 0.16),
            blurRadius: 16,
            spreadRadius: -2,
            offset: const Offset(0, 3),
          ),
        ],
      ),
    );
  }
}

class _LiquidHit extends StatelessWidget {
  const _LiquidHit({
    required this.destination,
    required this.selected,
    required this.badge,
    required this.onTap,
    this.iconSize = 22,
    this.labelSize = 10,
  });

  final LiquidDestination destination;
  final bool selected;
  final int badge;
  final VoidCallback onTap;
  final double iconSize;
  final double labelSize;

  @override
  Widget build(BuildContext context) {
    final color = selected ? const Color(0xFFEFFFFA) : const Color(0xFF8AA09F);
    final icon = Icon(destination.icon, size: iconSize, color: color);
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(16),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Badge(
            isLabelVisible: badge > 0,
            label: Text(badge > 99 ? '99+' : '$badge'),
            child: icon,
          ),
          const SizedBox(height: 4),
          Text(
            destination.label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: color,
              fontSize: labelSize,
              fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }
}

class _RailMoreHit extends StatelessWidget {
  const _RailMoreHit({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      key: const ValueKey('liquid-nav-rail-more'),
      onTap: onTap,
      borderRadius: BorderRadius.circular(14),
      child: const Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.apps_rounded, size: 20, color: IkoluColors.cyanSoft),
          SizedBox(height: 2),
          Text(
            'Ver todas',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: IkoluColors.cyanSoft,
              fontSize: 10,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}

class _RailAppHit extends StatelessWidget {
  const _RailAppHit({
    required this.app,
    required this.onTap,
    this.compact = false,
  });

  final LiquidAppShortcut app;
  final VoidCallback onTap;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final muted = app.comingSoon;
    final box = compact ? 32.0 : 40.0;
    final icon = compact ? 18.0 : 22.0;
    return Opacity(
      opacity: muted ? 0.72 : 1,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(14),
        child: Padding(
          padding: EdgeInsets.symmetric(
            horizontal: 10,
            vertical: compact ? 2 : 4,
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                width: box,
                height: box,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(compact ? 14 : 16),
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [
                      Color.lerp(app.color, Colors.white, 0.22)!,
                      app.color.withValues(alpha: 0.88),
                    ],
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: app.color.withValues(alpha: 0.28),
                      blurRadius: compact ? 6 : 10,
                      offset: const Offset(0, 3),
                    ),
                  ],
                ),
                child: Icon(
                  app.icon,
                  color: const Color(0xFFF4FFFC),
                  size: icon,
                ),
              ),
              SizedBox(height: compact ? 2 : 4),
              Text(
                app.label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: const Color(0xFFB7C9C8),
                  fontSize: compact ? 8 : 9,
                  fontWeight: FontWeight.w600,
                  letterSpacing: -0.2,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
