import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

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
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    const Color(0xFF163E44).withValues(alpha: 0.65),
                    const Color(0xFF08181D).withValues(alpha: 0.82),
                  ],
                ),
                border: Border.all(
                  color: const Color(0xFF66E0C2).withValues(alpha: 0.22),
                  width: 1.2,
                ),
                boxShadow: [
                  BoxShadow(
                    color: const Color(0xFF001217).withValues(alpha: 0.5),
                    blurRadius: 24,
                    offset: const Offset(0, 10),
                  ),
                  BoxShadow(
                    color: const Color(0xFF66E0C2).withValues(alpha: 0.08),
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
                            : const Duration(milliseconds: 420),
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
                                onTap: () {
                                  if (index != selectedIndex) {
                                    HapticFeedback.selectionClick();
                                  }
                                  onSelect(index);
                                },
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
    return ClipRect(
      child: BackdropFilter(
        filter: ui.ImageFilter.blur(sigmaX: 14, sigmaY: 14),
        child: Container(
          width: 92,
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [
                const Color(0xFF163E44).withValues(alpha: 0.42),
                const Color(0xFF0C1C21).withValues(alpha: 0.78),
              ],
            ),
            border: Border(
              right: BorderSide(
                color: const Color(0xFF66E0C2).withValues(alpha: 0.14),
              ),
            ),
          ),
          child: Stack(
            children: [
              AnimatedPositioned(
                duration: reduce
                    ? Duration.zero
                    : const Duration(milliseconds: 420),
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
                    for (
                      var index = 0;
                      index < liquidDestinations.length;
                      index++
                    )
                      SizedBox(
                        height: slot,
                        child: _LiquidHit(
                          destination: liquidDestinations[index],
                          selected: index == selectedIndex,
                          badge: index == 2 ? unreadCount : 0,
                          onTap: () {
                            if (index != selectedIndex) {
                              HapticFeedback.selectionClick();
                            }
                            onSelect(index);
                          },
                        ),
                      ),
                  ],
                ),
              ),
            ],
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
        borderRadius: BorderRadius.circular(22),
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            const Color(0xFF66E0C2).withValues(alpha: 0.38),
            const Color(0xFF14757C).withValues(alpha: 0.15),
          ],
        ),
        border: Border.all(
          color: const Color(0xFF66E0C2).withValues(alpha: 0.4),
          width: 1.2,
        ),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF66E0C2).withValues(alpha: 0.28),
            blurRadius: 14,
            spreadRadius: 1,
            offset: const Offset(0, 2),
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
    final reduce = MediaQuery.of(context).disableAnimations;
    final color = selected ? const Color(0xFFEFFFFA) : const Color(0xFF8AA09F);
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(20),
      splashColor: const Color(0xFF66E0C2).withValues(alpha: 0.12),
      highlightColor: const Color(0xFF66E0C2).withValues(alpha: 0.06),
      child: AnimatedScale(
        scale: selected ? 1.04 : 1,
        duration: reduce ? Duration.zero : const Duration(milliseconds: 280),
        curve: Curves.easeOutCubic,
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Badge(
              isLabelVisible: badge > 0,
              child: AnimatedSwitcher(
                duration: reduce
                    ? Duration.zero
                    : const Duration(milliseconds: 220),
                child: Icon(
                  destination.icon,
                  key: ValueKey('${destination.label}-$selected'),
                  size: selected ? 23 : 22,
                  color: color,
                ),
              ),
            ),
            const SizedBox(height: 2),
            AnimatedDefaultTextStyle(
              duration: reduce
                  ? Duration.zero
                  : const Duration(milliseconds: 240),
              curve: Curves.easeOutCubic,
              style: TextStyle(
                color: color,
                fontSize: 10,
                fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
              ),
              child: Text(destination.label),
            ),
          ],
        ),
      ),
    );
  }
}
