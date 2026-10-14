import 'dart:ui' as ui;
import 'package:flutter/material.dart';

import '../../core/brand.dart';

class LiquidDestination {
  const LiquidDestination({required this.icon, required this.label});

  final IconData icon;
  final String label;
}

const liquidDestinations = <LiquidDestination>[
  LiquidDestination(icon: Icons.grid_view_rounded, label: 'Inicio'),
  LiquidDestination(icon: Icons.water_drop_outlined, label: 'Puntos'),
  LiquidDestination(icon: Icons.notifications_none_rounded, label: 'Avisos'),
  LiquidDestination(icon: Icons.apps_rounded, label: 'Más'),
  LiquidDestination(icon: Icons.person_outline_rounded, label: 'Perfil'),
];

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
                      // Cápsula iluminada debajo del ítem activo
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
                                badge: index == 2 ? unreadCount : 0,
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

class LiquidNavRail extends StatelessWidget {
  const LiquidNavRail({
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
    const slot = 72.0;
    const top = 20.0;
    return Container(
      width: 92,
      decoration: BoxDecoration(
        color: const Color(0xFF0C1C21).withValues(alpha: 0.72),
        border: Border(
          right: BorderSide(color: Colors.white.withValues(alpha: 0.07)),
        ),
      ),
      child: Stack(
        children: [
          AnimatedPositioned(
            duration: reduce
                ? Duration.zero
                : const Duration(milliseconds: 460),
            curve: Curves.easeOutCubic,
            top: top + slot * selectedIndex + 4,
            left: 10,
            right: 10,
            height: slot - 8,
            child: const _LiquidBlob(),
          ),
          Padding(
            padding: const EdgeInsets.only(top: top),
            child: Column(
              children: [
                for (var index = 0; index < liquidDestinations.length; index++)
                  SizedBox(
                    height: slot,
                    child: _LiquidHit(
                      destination: liquidDestinations[index],
                      selected: index == selectedIndex,
                      badge: index == 2 ? unreadCount : 0,
                      onTap: () => onSelect(index),
                    ),
                  ),
              ],
            ),
          ),
        ],
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
        borderRadius: BorderRadius.circular(22),
        // Cápsula del ítem activo: relleno suave sin borde marcado.
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
  });

  final LiquidDestination destination;
  final bool selected;
  final int badge;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final color = selected ? const Color(0xFFEFFFFA) : const Color(0xFF8AA09F);
    final icon = Icon(destination.icon, size: 22, color: color);
    return InkWell(
      onTap: onTap,
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Badge(isLabelVisible: badge > 0, child: icon),
          const SizedBox(height: 2),
          Text(
            destination.label,
            style: TextStyle(
              color: color,
              fontSize: 10,
              fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }
}
