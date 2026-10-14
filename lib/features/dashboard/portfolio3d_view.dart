import 'package:flutter/material.dart';

import 'portfolio3d_view_stub.dart'
    if (dart.library.html) 'portfolio3d_view_web.dart'
    as impl;

bool get portfolio3dSupported => impl.portfolio3dSupported;

void portfolio3dDim(double opacity) => impl.portfolio3dDim(opacity);

/// Ciudad WebGL. En web es un iframe Three.js; en otras plataformas no pinta.
class PortfolioCityView extends StatelessWidget {
  const PortfolioCityView({
    required this.points,
    required this.onSelect,
    this.onPageDown,
    this.selected,
    super.key,
  });

  final List<Map<String, dynamic>> points;
  final ValueChanged<int?> onSelect;
  final VoidCallback? onPageDown;
  final int? selected;

  @override
  Widget build(BuildContext context) {
    return impl.PortfolioCityWeb(
      points: points,
      onSelect: onSelect,
      onPageDown: onPageDown,
      selected: selected,
    );
  }
}
