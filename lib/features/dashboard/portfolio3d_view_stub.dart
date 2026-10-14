import 'package:flutter/material.dart';

const bool portfolio3dSupported = false;

void portfolio3dDim(double opacity) {}

class PortfolioCityWeb extends StatelessWidget {
  const PortfolioCityWeb({
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
  Widget build(BuildContext context) => const SizedBox.shrink();
}
