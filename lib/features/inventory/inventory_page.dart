import 'package:flutter/material.dart';

import '../../core/widgets/feature_placeholder.dart';

class InventoryPage extends StatelessWidget {
  const InventoryPage({super.key});

  @override
  Widget build(BuildContext context) {
    return const FeaturePlaceholder(
      icon: Icons.inventory_2_outlined,
      title: 'Inventory',
      description:
          'Manage gas products (size × brand), live stock levels per branch, '
          'stock-in from suppliers, adjustments and low-stock alerts.',
      upcoming: [
        'Products: add/edit gas cylinders (6kg, 13kg, 50kg…)',
        'Stock levels & low-stock alerts',
        'Stock adjustments (losses, corrections)',
        'Supplier purchases & payables',
        'Branch transfers',
      ],
    );
  }
}
