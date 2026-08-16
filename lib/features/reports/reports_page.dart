import 'package:flutter/material.dart';

import '../../core/widgets/feature_placeholder.dart';

class ReportsPage extends StatelessWidget {
  const ReportsPage({super.key});

  @override
  Widget build(BuildContext context) {
    return const FeaturePlaceholder(
      icon: Icons.bar_chart_outlined,
      title: 'Reports',
      description:
          'Daily sales, VAT summary, best sellers, stock valuation and '
          'debtors — exportable to CSV/PDF for records.',
      upcoming: [
        'Daily / weekly / monthly sales summary',
        'Best-selling products',
        'Stock valuation & movement log',
        'Debtors & credit aging',
        'VAT (16%) summary',
        'Export to CSV / print',
      ],
    );
  }
}
